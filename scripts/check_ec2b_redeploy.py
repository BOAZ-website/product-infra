#!/usr/bin/env python3
"""EC2-B 재배포 순서 게이트 (CMP-03-01, docs/guides/season-runbook.md 3단계).

시즌 시작 때 EC2-B를 Target Group에 등록하기 전에 실행한다. 순서는
"EC2-B 기동 → 최신 번들 재배포 성공 → Target Group 등록"이며, 아래가 모두 맞아야 통과(exit 0)한다.
하나라도 어긋나면 실패(exit 1), 입력·조회 오류는 exit 2.

  R1 EC2-B가 running
  R2 EC2-B에 CodeDeploy 대상 태그(app=boaz-api)가 있음
  R3 EC2-B를 켠 뒤 배포 그룹에 만든 배포가 하나 이상 있음
  R4 배포 그룹에 진행·대기 중인 배포가 없음
  R5 그 배포 가운데 가장 최근 배포가 성공(Succeeded)
  R6 가장 최근 배포에서 EC2-A·B 대상이 모두 성공
  R7 EC2-B가 아직 Target Group에 등록되어 있지 않음(재배포 확인 전에 등록한 경우를 실패로 판정)

입력 값은 SSM `/boaz/infra/*` String 파라미터(EC2_B_ID, CODEDEPLOY_APP, CODEDEPLOY_GROUP,
TARGET_GROUP_ARN)과 /boaz/terraform/group-vars의 compute에서 읽는다. AWS 조회는 읽기 전용이며
출력에는 규칙과 사유만 쓰고 자원 ID는 쓰지 않는다(공개 저장소).
--wait-target-health는 origin 교체 전에 예상한 EC2-A·B의 등록과 상태를 확인한다.

  AWS_PROFILE=boaz python3 scripts/check_ec2b_redeploy.py

외부 패키지 없이 표준 라이브러리와 AWS CLI만 사용한다.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable

try:  # 직접 실행: python3 scripts/check_ec2b_redeploy.py / pytest: from scripts import check_ec2b_redeploy
    from plan_summary import redact
except ImportError:  # pragma: no cover
    from scripts.plan_summary import redact

REGION = "ap-northeast-2"
PARAM_PREFIX = "/boaz/infra/"
PARAM_KEYS = ("EC2_B_ID", "CODEDEPLOY_APP", "CODEDEPLOY_GROUP", "TARGET_GROUP_ARN")
HEALTH_PARAM_KEYS = ("EC2_B_ID", "TARGET_GROUP_ARN", "EC2_A_PORT")
GROUP_VARS_PARAMETER = "/boaz/terraform/group-vars"
HEALTH_TIMEOUT_SECONDS = 900
HEALTH_POLL_SECONDS = 15

# CodeDeploy 대상 태그. 배포 그룹 ec2_tag_set과 같아야 EC2-B가 배포 대상에 들어감(DEP-02)
TARGET_TAG = ("app", "boaz-api")

# 끝나지 않은 배포 상태(CodeDeploy DeploymentStatus)
IN_PROGRESS = ("Created", "Queued", "InProgress", "Baking", "Ready")


@dataclass(frozen=True)
class Deployment:
    created: datetime
    status: str
    target_statuses: tuple[str | None, str | None]  # EC2-A·B 순서. 대상에 없으면 None


@dataclass(frozen=True)
class Facts:
    ec2b_state: str
    ec2b_launch: datetime  # 마지막으로 켠 시각(EC2 LaunchTime)
    ec2b_tags: dict[str, str]
    deployments: list[Deployment]  # 배포 그룹의 배포(EC2-B를 켠 뒤 만든 것)
    ec2b_registered: bool  # Target Group에 EC2-B가 등록되어 있는지
    active_deployments: int


@dataclass(frozen=True)
class Violation:
    rule: str
    reason: str

    def render(self) -> str:
        return f"- `{self.rule}` {self.reason}"


class CollectError(Exception):
    """AWS 조회 실패나 입력 값 누락. 메시지에는 자원 ID를 넣지 않는다."""


def evaluate(facts: Facts) -> list[Violation]:
    """조회 결과로 규칙 R1~R7을 판정해 위반 목록을 돌려준다. 빈 목록이면 통과."""
    out: list[Violation] = []

    if facts.ec2b_state != "running":
        out.append(Violation("R1", f"EC2-B가 running이 아님(현재 {facts.ec2b_state}). EC2-B를 먼저 켬"))

    key, value = TARGET_TAG
    if facts.ec2b_tags.get(key) != value:
        out.append(Violation("R2", f"EC2-B에 `{key}={value}` 태그가 없음. 태그가 없으면 재배포 대상에서 빠짐"))

    after_launch = [d for d in facts.deployments if d.created >= facts.ec2b_launch]
    if not after_launch:
        out.append(Violation("R3", "EC2-B를 켠 뒤 만든 배포가 없음. 최신 번들 재배포를 먼저 실행함"))

    if facts.active_deployments:
        out.append(Violation("R4", f"진행·대기 중인 배포가 {facts.active_deployments}건 있음. 끝날 때까지 기다림"))

    if after_launch:
        latest = max(after_launch, key=lambda d: d.created)
        if latest.status != "Succeeded":
            out.append(Violation("R5", f"가장 최근 배포가 성공하지 않음(상태 {latest.status})"))
        for role, status in zip(("A", "B"), latest.target_statuses, strict=True):
            if status is None:
                out.append(Violation("R6", f"가장 최근 배포 대상에 EC2-{role}가 없음"))
            elif status != "Succeeded":
                out.append(Violation("R6", f"가장 최근 배포에서 EC2-{role} 대상이 성공하지 않음(상태 {status})"))

    if facts.ec2b_registered:
        out.append(
            Violation("R7", "EC2-B가 이미 Target Group에 등록되어 있음. 재배포 성공을 확인하기 전에 등록하면 안 됨")
        )

    return out


def render(violations: list[Violation]) -> str:
    if not violations:
        return (
            "#### EC2-B 재배포 순서 게이트: ✅ 통과\n\n"
            "EC2-B 기동, 대상 태그, 기동 뒤 EC2-A·B 재배포 성공, EC2-B Target Group 미등록 확인. 등록 단계로 진행 가능"
        )
    lines = ["#### EC2-B 재배포 순서 게이트: ❌ 실패", "", "Target Group 등록으로 진행하지 않음", ""]
    lines += [v.render() for v in violations]
    return "\n".join(lines)


def parse_time(value: object) -> datetime:
    """AWS CLI JSON의 시각(ISO 8601 문자열 또는 epoch 초)을 UTC 기준 datetime으로 바꾼다."""
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    if isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    raise CollectError(f"시각 형식을 알 수 없음({type(value).__name__})")


Runner = Callable[[list[str]], dict]


def aws_cli(args: list[str]) -> dict:
    """AWS CLI를 JSON 출력으로 실행한다. 실패 메시지는 식별자를 가린 뒤 넘긴다."""
    cmd = ["aws", *args, "--region", os.environ.get("AWS_REGION", REGION), "--output", "json"]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=30)
    if proc.returncode != 0:
        detail = redact(proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "")
        raise CollectError(f"`aws {args[0]} {args[1]}` 실패: {detail}")
    return json.loads(proc.stdout or "{}")


def _chunks(items: list[str], size: int) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def read_parameters(run: Runner, keys: tuple[str, ...]) -> dict[str, str]:
    names = [PARAM_PREFIX + key for key in keys]
    resp = run(["ssm", "get-parameters", "--names", *names])
    params = {p["Name"].removeprefix(PARAM_PREFIX): p for p in resp["Parameters"]}
    missing = [key for key in keys if key not in params]
    if missing:
        raise CollectError(f"SSM 파라미터 없음: {', '.join(missing)}")
    if any(params[key].get("Type") != "String" for key in keys):
        raise CollectError("SSM 파라미터가 String 유형이 아님(SecureString은 복호화하지 않음)")
    return {key: params[key]["Value"] for key in keys}


def read_compute_ids(run: Runner, params: dict[str, str]) -> tuple[str, str]:
    param = run(["ssm", "get-parameter", "--name", GROUP_VARS_PARAMETER])["Parameter"]
    if param.get("Type") != "String":
        raise CollectError("Terraform 그룹 값이 String 유형이 아님")
    compute = json.loads(param["Value"])["compute"]
    ids = compute["instance_ids"]
    ec2a, ec2b = ids["ec2_a"], ids["ec2_b"]
    if not ec2a or not ec2b or ec2a == ec2b:
        raise CollectError("Terraform 그룹 값에 서로 다른 EC2-A·B ID가 필요함")
    if ec2b != params["EC2_B_ID"] or compute["target_group_arn"] != params["TARGET_GROUP_ARN"]:
        raise CollectError("시즌과 Terraform 파라미터의 EC2-B 또는 Target Group 값이 다름")
    return ec2a, ec2b


def collect(run: Runner = aws_cli) -> Facts:
    """읽기 전용 AWS 조회로 판정에 필요한 값을 모은다."""
    params = read_parameters(run, PARAM_KEYS)
    ec2a, ec2b = read_compute_ids(run, params)
    app = params["CODEDEPLOY_APP"]
    group = params["CODEDEPLOY_GROUP"]
    tg = params["TARGET_GROUP_ARN"]

    reservations = run(["ec2", "describe-instances", "--instance-ids", ec2b]).get("Reservations", [])
    instances = [i for r in reservations for i in r.get("Instances", [])]
    if len(instances) != 1:
        raise CollectError("EC2-B 인스턴스를 찾지 못함")
    inst = instances[0]
    launch = parse_time(inst["LaunchTime"])
    tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}

    start = launch.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    group_query = ["deploy", "list-deployments", "--application-name", app, "--deployment-group-name", group]
    ids = run([*group_query, "--create-time-range", f"start={start}"])["deployments"]

    infos: list[dict] = []
    for chunk in _chunks(ids, 25):  # batch-get-deployments 한 번에 25건까지
        batch = run(["deploy", "batch-get-deployments", "--deployment-ids", *chunk])["deploymentsInfo"]
        if sorted(info["deploymentId"] for info in batch) != sorted(chunk):
            raise CollectError("요청한 배포의 상세 조회 결과가 누락되거나 중복됨")
        infos.extend(batch)
    infos.sort(key=lambda info: parse_time(info["createTime"]))
    if len(infos) > 1 and parse_time(infos[-1]["createTime"]) == parse_time(infos[-2]["createTime"]):
        raise CollectError("최근 배포의 생성 시각이 같아 어느 배포를 검증해야 하는지 구분할 수 없음")

    deployments: list[Deployment] = []
    for i, info in enumerate(infos):
        # 대상 상태는 판정에 쓰는 가장 최근 배포만 조회함
        statuses = (None, None)
        if i == len(infos) - 1:
            statuses = deployment_target_statuses(run, info["deploymentId"], ec2a, ec2b)
        deployments.append(Deployment(parse_time(info["createTime"]), info["status"], statuses))

    # 기동 전에 요청됐더라도 아직 진행 중인 배포는 등록을 막음
    active = set(run([*group_query, "--include-only-statuses", *IN_PROGRESS])["deployments"])
    active.update(info["deploymentId"] for info in infos if info["status"] in IN_PROGRESS)

    health = target_health(run, tg)
    registered = any(row["Target"]["Id"] == ec2b for row in health)
    return Facts(inst["State"]["Name"], launch, tags, deployments, registered, len(active))


def deployment_target_statuses(run: Runner, deployment_id: str, ec2a: str, ec2b: str) -> tuple[str | None, str | None]:
    target_ids = run(["deploy", "list-deployment-targets", "--deployment-id", deployment_id])["targetIds"]

    def status(instance_id: str) -> str | None:
        if instance_id not in target_ids:
            return None
        target = run(["deploy", "get-deployment-target", "--deployment-id", deployment_id, "--target-id", instance_id])
        return target["deploymentTarget"]["instanceTarget"]["status"]

    return status(ec2a), status(ec2b)


def target_health(run: Runner, target_group_arn: str) -> list[dict]:
    return run(["elbv2", "describe-target-health", "--target-group-arn", target_group_arn])["TargetHealthDescriptions"]


def expected_targets_are_healthy(rows: list[dict], ec2a: str, ec2b: str, port: int) -> bool:
    expected = {(ec2a, port), (ec2b, port)}
    healthy = {
        (row["Target"]["Id"], row["Target"]["Port"])
        for row in rows
        if row["TargetHealth"]["State"] == "healthy"
    }
    return len(rows) == len(expected) and healthy == expected


def wait_target_health(run: Runner = aws_cli) -> int:
    params = read_parameters(run, HEALTH_PARAM_KEYS)
    ec2a, ec2b = read_compute_ids(run, params)
    port = int(params["EC2_A_PORT"])
    deadline = time.monotonic() + HEALTH_TIMEOUT_SECONDS
    print("EC2-A·B의 Target Group 상태를 최대 15분 동안 확인함", flush=True)

    while True:
        rows = target_health(run, params["TARGET_GROUP_ARN"])
        if expected_targets_are_healthy(rows, ec2a, ec2b, port):
            print("EC2-A·B가 예상 포트에 등록됐고 둘 다 healthy임. origin 교체 진행 가능")
            return 0
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print("15분 안에 EC2-A·B의 등록과 healthy 상태가 모두 확인되지 않음. origin 교체 중단")
            return 1
        time.sleep(min(HEALTH_POLL_SECONDS, remaining))


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args not in ([], ["--wait-target-health"]):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if args:
            return wait_target_health()
        violations = evaluate(collect())
    except (CollectError, KeyError, OSError, TypeError, ValueError, subprocess.TimeoutExpired) as exc:
        reason = str(exc) if isinstance(exc, CollectError) else f"응답 형식 오류({type(exc).__name__})"
        print(f"#### 시즌 전환 검증: ❌ 조회 실패\n\n{reason}")
        return 2
    print(render(violations))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
