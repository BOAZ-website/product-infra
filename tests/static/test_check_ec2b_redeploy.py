"""scripts/check_ec2b_redeploy.py 고정 입력 검사 (CMP-03-01).

"EC2-B 기동 → 최신 번들 재배포 성공 → Target Group 등록" 순서가 맞는 경우만 통과하고, 재배포 전에 등록한 경우를
포함해 순서가 어긋난 경우는 실패하는지 확인한다. AWS에 요청하지 않는다(조회 함수는 가짜 응답으로 대체).
공개 저장소 검사에 걸리지 않도록 식별자는 실제 형식을 흉내 내지 않는다.
"""

import json
from dataclasses import replace
from datetime import datetime, timedelta, timezone

import pytest

from scripts import check_ec2b_redeploy as gate

LAUNCH = datetime(2026, 12, 1, 3, 0, tzinfo=timezone.utc)


def dep(minutes: int, status: str = "Succeeded", ec2b: str | None = "Succeeded") -> gate.Deployment:
    """EC2-B를 켠 시각 기준 minutes분 뒤에 만든 배포."""
    return gate.Deployment(LAUNCH + timedelta(minutes=minutes), status, ("Succeeded", ec2b))


def ok_facts(**changes) -> gate.Facts:
    base = gate.Facts(
        ec2b_state="running",
        ec2b_launch=LAUNCH,
        ec2b_tags={"Name": "fake-ec2-b", "Environment": "prod", "app": "boaz-api"},
        deployments=[dep(5)],
        ec2b_registered=False,
        active_deployments=0,
        deployment_list_changed=False,
    )
    return replace(base, **changes)


def rules(facts: gate.Facts) -> list[str]:
    return [v.rule for v in gate.evaluate(facts)]


def test_passes_when_order_is_kept():
    assert rules(ok_facts()) == []


def test_registered_before_redeploy_fails():
    # 재배포 없이 등록부터 한 경우(명세 CMP-03-01 완료 확인 방법)
    assert rules(ok_facts(deployments=[], ec2b_registered=True)) == ["R3", "R7"]


def test_registered_after_redeploy_also_fails():
    # 게이트는 등록 전에 실행함. 이미 등록되어 있으면 순서를 확인할 수 없으므로 실패로 둠
    assert rules(ok_facts(ec2b_registered=True)) == ["R7"]


@pytest.mark.parametrize("state", ["stopped", "pending", "stopping"])
def test_ec2b_not_running_fails(state):
    assert "R1" in rules(ok_facts(ec2b_state=state))


@pytest.mark.parametrize(
    "tags",
    [{}, {"app": "other"}, {"App": "boaz-api"}],
    ids=["no-tag", "other-value", "key-case"],
)
def test_missing_target_tag_fails(tags):
    assert rules(ok_facts(ec2b_tags=tags)) == ["R2"]


def test_deployment_before_launch_does_not_count():
    # EC2-B를 켜기 전 배포는 EC2-B에 최신 번들을 넣지 않았으므로 재배포로 치지 않음
    assert rules(ok_facts(deployments=[dep(-30)])) == ["R3"]


def test_deployment_in_progress_fails():
    facts = ok_facts(
        deployments=[dep(5), dep(10, status="InProgress", ec2b="InProgress")],
        active_deployments=1,
    )
    assert rules(facts) == ["R4", "R5", "R6"]


def test_latest_failed_after_earlier_success_fails():
    # 성공한 재배포 뒤에 실패한 배포가 있으면 지금 EC2-B 앱 상태를 믿을 수 없음
    assert rules(ok_facts(deployments=[dep(5), dep(20, status="Failed", ec2b="Failed")])) == ["R5", "R6"]


def test_latest_order_uses_create_time_not_list_order():
    assert rules(ok_facts(deployments=[dep(20), dep(5, status="Failed", ec2b="Failed")])) == []


def test_ec2b_missing_from_latest_targets_fails():
    # 태그를 붙이기 전에 만든 배포는 EC2-A만 대상으로 함
    assert rules(ok_facts(deployments=[dep(5, ec2b=None)])) == ["R6"]


def test_ec2b_target_failed_fails():
    assert rules(ok_facts(deployments=[dep(5, ec2b="Failed")])) == ["R6"]


def test_render_has_no_identifiers():
    facts = ok_facts(ec2b_state="stopped", deployments=[], ec2b_registered=True)
    text = gate.render(gate.evaluate(facts))
    assert "❌ 실패" in text
    assert "fake-" not in text
    assert "✅ 통과" in gate.render([])


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("2026-12-01T03:00:00+00:00", LAUNCH),
        ("2026-12-01T12:00:00.123000+09:00", LAUNCH + timedelta(milliseconds=123)),
        ("2026-12-01T03:00:00Z", LAUNCH),
        (LAUNCH.timestamp(), LAUNCH),
    ],
)
def test_parse_time(value, expected):
    assert gate.parse_time(value) == expected


# collect(): AWS CLI 응답을 가짜로 주고 Facts가 맞게 조립되는지 확인

EC2B = "fake-ec2-b"
EC2A = "fake-ec2-a"
TG = "fake-tg"


class FakeAws:
    def __init__(
        self, *, params=None, registered=(EC2A,), deployments=None,
        latest_targets=(EC2A, EC2B), active=(), omitted=(), target_statuses=None,
    ):
        self.calls: list[list[str]] = []
        self.params = params if params is not None else {
            "EC2_A_PORT": "8080",
            "EC2_B_ID": EC2B,
            "CODEDEPLOY_APP": "fake-app",
            "CODEDEPLOY_GROUP": "fake-group",
            "TARGET_GROUP_ARN": TG,
        }
        self.registered = registered
        # (배포 ID, 생성 시각 문자열, 상태)
        self.deployments = deployments if deployments is not None else [
            ("fake-d2", "2026-12-01T12:20:00+09:00", "Succeeded"),
            ("fake-d1", "2026-12-01T12:05:00+09:00", "Failed"),
        ]
        self.latest_targets = latest_targets
        self.active = active
        self.omitted = omitted
        self.target_statuses = target_statuses or {EC2A: "Succeeded", EC2B: "Succeeded"}

    def __call__(self, args: list[str]) -> dict:
        self.calls.append(args)
        op = (args[0], args[1])
        if op == ("ssm", "get-parameters"):
            return {
                "Parameters": [
                    {"Name": "/boaz/infra/" + k, "Type": "String", "Value": v} for k, v in self.params.items()
                ],
                "InvalidParameters": [],
            }
        if op == ("ssm", "get-parameter"):
            return {"Parameter": {"Type": "String", "Value": json.dumps({
                "compute": {"instance_ids": {"ec2_a": EC2A, "ec2_b": EC2B}, "target_group_arn": TG},
            })}}
        if op == ("ec2", "describe-instances"):
            return {
                "Reservations": [
                    {
                        "Instances": [
                            {
                                "State": {"Name": "running"},
                                "LaunchTime": "2026-12-01T03:00:00+00:00",
                                "Tags": [{"Key": "app", "Value": "boaz-api"}],
                            }
                        ]
                    }
                ]
            }
        if op == ("deploy", "list-deployments"):
            if "--include-only-statuses" in args:
                return {"deployments": list(self.active)}
            return {"deployments": [d[0] for d in self.deployments]}
        if op == ("deploy", "batch-get-deployments"):
            wanted = set(args[args.index("--deployment-ids") + 1 :])
            return {
                "deploymentsInfo": [
                    {"deploymentId": i, "createTime": t, "status": s}
                    for i, t, s in self.deployments if i in wanted and i not in self.omitted
                ]
            }
        if op == ("deploy", "list-deployment-targets"):
            return {"targetIds": list(self.latest_targets)}
        if op == ("deploy", "get-deployment-target"):
            target = args[-1]
            return {"deploymentTarget": {"instanceTarget": {"targetId": target, "status": self.target_statuses[target]}}}
        if op == ("elbv2", "describe-target-health"):
            return {"TargetHealthDescriptions": [healthy_target(i) for i in self.registered]}
        raise AssertionError(f"예상하지 않은 호출: {op}")


def test_collect_builds_facts_and_passes():
    fake = FakeAws()
    facts = gate.collect(fake)
    assert facts.ec2b_state == "running" and facts.ec2b_launch == LAUNCH
    assert [d.status for d in facts.deployments] == ["Failed", "Succeeded"]  # 생성 시각 순
    assert facts.deployments[-1].target_statuses == ("Succeeded", "Succeeded")
    assert facts.ec2b_registered is False
    assert gate.evaluate(facts) == []
    # 배포 조회 범위를 EC2-B를 켠 시각부터로 좁힘
    list_call = next(c for c in fake.calls if c[:2] == ["deploy", "list-deployments"])
    assert list_call[list_call.index("--create-time-range") + 1] == "start=2026-12-01T03:00:00Z"


def test_collect_uses_only_read_operations():
    fake = FakeAws()
    gate.collect(fake)
    for service, operation, *_ in fake.calls:
        assert operation.split("-")[0] in {"get", "list", "describe", "batch"}, (service, operation)


def test_collect_detects_registered_ec2b():
    assert gate.collect(FakeAws(registered=(EC2A, EC2B))).ec2b_registered is True


def test_collect_marks_ec2b_missing_from_targets():
    facts = gate.collect(FakeAws(latest_targets=(EC2A,)))
    assert rules(facts) == ["R6"]


def test_collect_chunks_batch_requests():
    many = [(f"fake-d{i:02d}", f"2026-12-01T03:{i:02d}:00+00:00", "Succeeded") for i in range(30)]
    fake = FakeAws(deployments=many)
    facts = gate.collect(fake)
    batches = [c for c in fake.calls if c[:2] == ["deploy", "batch-get-deployments"]]
    assert [len(c) - 3 for c in batches] == [25, 5]
    assert len(facts.deployments) == 30


def test_collect_missing_parameter_is_error():
    params = {"EC2_B_ID": EC2B, "CODEDEPLOY_APP": "fake-app", "CODEDEPLOY_GROUP": "fake-group"}
    with pytest.raises(gate.CollectError, match="TARGET_GROUP_ARN"):
        gate.collect(FakeAws(params=params))


def test_collect_active_deployment_checks_entire_group():
    fake = FakeAws(active=("fake-deployment-before-launch",))
    assert rules(gate.collect(fake)) == ["R4"]
    active_call = next(call for call in fake.calls if "--include-only-statuses" in call)
    assert "--create-time-range" not in active_call


@pytest.mark.parametrize("second_listing,expected_exit", [
    (["fake-d2", "fake-d1", "fake-new-deployment"], 1),
    (["fake-d1", "fake-d2"], 0),
], ids=["new-deployment-finished-between-reads", "same-ids-in-different-order"])
def test_deployment_list_is_checked_again_before_passing(second_listing, expected_exit, monkeypatch):
    class ChangingListing(FakeAws):
        def __call__(self, args):
            result = super().__call__(args)
            if "--create-time-range" in args and sum("--create-time-range" in call for call in self.calls) == 2:
                return {"deployments": second_listing}
            return result

    facts = gate.collect(ChangingListing())
    monkeypatch.setattr(gate, "collect", lambda: facts)
    assert facts.active_deployments == 0
    assert gate.main(["check_ec2b_redeploy.py"]) == expected_exit
    assert rules(facts) == (["R4"] if expected_exit else [])


def test_collect_fails_when_deployment_details_are_missing():
    with pytest.raises(gate.CollectError, match="상세 조회 결과"):
        gate.collect(FakeAws(omitted=("fake-d2",)))


def test_collect_fails_when_latest_deployment_is_ambiguous():
    same_time = "2026-12-01T03:05:00+00:00"
    fake = FakeAws(deployments=[("fake-d1", same_time, "Failed"), ("fake-d2", same_time, "Succeeded")])
    with pytest.raises(gate.CollectError, match="생성 시각"):
        gate.collect(fake)


def test_collect_detects_failed_ec2a_even_if_deployment_succeeded():
    facts = gate.collect(FakeAws(target_statuses={EC2A: "Failed", EC2B: "Succeeded"}))
    violations = gate.evaluate(facts)
    assert [v.rule for v in violations] == ["R6"]
    assert "EC2-A" in violations[0].reason


def healthy_target(instance_id, port=8080, state="healthy"):
    return {"Target": {"Id": instance_id, "Port": port}, "TargetHealth": {"State": state}}


@pytest.mark.parametrize(
    ("rows", "ready"),
    [
        ([healthy_target(EC2B), healthy_target(EC2A)], True),
        ([healthy_target(EC2A)], False),
        ([healthy_target(EC2A), healthy_target("fake-other-ec2")], False),
        ([healthy_target(EC2A), healthy_target(EC2B, port=80)], False),
        ([healthy_target(EC2A), healthy_target(EC2B, state="initial")], False),
        ([healthy_target(EC2A), healthy_target(EC2B), healthy_target("fake-other-ec2")], False),
    ],
    ids=["both", "one", "wrong-instance", "wrong-port", "unhealthy", "extra"],
)
def test_origin_requires_exact_healthy_targets(rows, ready):
    assert gate.expected_targets_are_healthy(rows, EC2A, EC2B, 8080) is ready


def test_wait_target_health_stops_if_one_target_is_missing(monkeypatch):
    monkeypatch.setattr(gate, "HEALTH_TIMEOUT_SECONDS", 0)
    assert gate.wait_target_health(FakeAws(registered=(EC2A,))) == 1


def test_wait_target_health_passes_when_both_targets_are_healthy():
    assert gate.wait_target_health(FakeAws(registered=(EC2A, EC2B))) == 0
