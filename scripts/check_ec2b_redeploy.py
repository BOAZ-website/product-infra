#!/usr/bin/env python3
"""EC2-B 재배포 순서 게이트 (CMP-03-01, docs/guides/season-runbook.md 3단계).

시즌 시작 때 EC2-B를 Target Group에 등록하기 전에 실행한다. 순서는
"EC2-B 기동 → 최신 번들 재배포 성공 → Target Group 등록"이며, 아래가 모두 맞아야 통과(exit 0)한다.
하나라도 어긋나면 실패(exit 1), 입력·조회 오류는 exit 2.

  R1 EC2-B가 running
  R2 EC2-B에 CodeDeploy 대상 태그(app=boaz-api)가 있음
  R3 EC2-B를 켠 뒤 배포 그룹에 만든 배포가 하나 이상 있음
  R4 그 배포 가운데 진행 중인 배포가 없음
  R5 그 배포 가운데 가장 최근 배포가 성공(Succeeded)
  R6 가장 최근 배포에서 EC2-B 대상이 성공
  R7 EC2-B가 아직 Target Group에 등록되어 있지 않음(재배포 확인 전에 등록한 경우를 실패로 판정)

입력 값은 SSM `/boaz/infra/*` String 파라미터(EC2_B_ID, CODEDEPLOY_APP, CODEDEPLOY_GROUP,
TARGET_GROUP_ARN)에서 읽는다. AWS 조회는 읽기 전용(describe·list·get)만 쓰고, 출력에는 규칙과 사유만
쓰며 자원 ID는 쓰지 않는다(공개 저장소).

  AWS_PROFILE=boaz python3 scripts/check_ec2b_redeploy.py

외부 패키지 없이 표준 라이브러리와 AWS CLI만 사용한다.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
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

# CodeDeploy 대상 태그. 배포 그룹 ec2_tag_set과 같아야 EC2-B가 배포 대상에 들어감(DEP-02)
TARGET_TAG = ("app", "boaz-api")

# 끝나지 않은 배포 상태(CodeDeploy DeploymentStatus)
IN_PROGRESS = frozenset({"Created", "Queued", "InProgress", "Baking", "Ready"})


@dataclass(frozen=True)
class Deployment:
    created: datetime
    status: str
    ec2b_status: str | None  # 이 배포에서 EC2-B 대상의 상태. 대상에 없으면 None


@dataclass(frozen=True)
class Facts:
    ec2b_state: str
    ec2b_launch: datetime  # 마지막으로 켠 시각(EC2 LaunchTime)
    ec2b_tags: dict[str, str]
    deployments: list[Deployment]  # 배포 그룹의 배포(EC2-B를 켠 뒤 만든 것)
    ec2b_registered: bool  # Target Group에 EC2-B가 등록되어 있는지


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
    else:
        running = [d for d in after_launch if d.status in IN_PROGRESS]
        if running:
            out.append(Violation("R4", f"진행 중인 배포가 {len(running)}건 있음. 끝날 때까지 기다림"))

        latest = max(after_launch, key=lambda d: d.created)
        if latest.status != "Succeeded":
            out.append(Violation("R5", f"가장 최근 배포가 성공하지 않음(상태 {latest.status})"))
        if latest.ec2b_status is None:
            out.append(Violation("R6", "가장 최근 배포 대상에 EC2-B가 없음. 태그를 붙이기 전에 만든 배포일 수 있음"))
        elif latest.ec2b_status != "Succeeded":
            out.append(Violation("R6", f"가장 최근 배포에서 EC2-B 대상이 성공하지 않음(상태 {latest.ec2b_status})"))

    if facts.ec2b_registered:
        out.append(
            Violation("R7", "EC2-B가 이미 Target Group에 등록되어 있음. 재배포 성공을 확인하기 전에 등록하면 안 됨")
        )

    return out


def render(violations: list[Violation]) -> str:
    if not violations:
        return (
            "#### EC2-B 재배포 순서 게이트: ✅ 통과\n\n"
            "EC2-B 기동, 대상 태그, 기동 뒤 재배포 성공, Target Group 미등록 확인. 등록 단계로 진행 가능"
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
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        detail = redact(proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "")
        raise CollectError(f"`aws {args[0]} {args[1]}` 실패: {detail}")
    return json.loads(proc.stdout or "{}")


def _chunks(items: list[str], size: int) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def collect(run: Runner = aws_cli) -> Facts:
    """읽기 전용 AWS 조회로 판정에 필요한 값을 모은다."""
    names = [PARAM_PREFIX + k for k in PARAM_KEYS]
    resp = run(["ssm", "get-parameters", "--names", *names])
    params = {p["Name"].removeprefix(PARAM_PREFIX): p for p in resp.get("Parameters", [])}
    missing = [k for k in PARAM_KEYS if k not in params]
    if missing:
        raise CollectError(f"SSM 파라미터 없음: {', '.join(missing)}")
    if any(params[k].get("Type") != "String" for k in PARAM_KEYS):
        raise CollectError("SSM 파라미터가 String 유형이 아님(SecureString은 읽지 않음)")
    ec2b, app, group, tg = (params[k]["Value"] for k in PARAM_KEYS)

    reservations = run(["ec2", "describe-instances", "--instance-ids", ec2b]).get("Reservations", [])
    instances = [i for r in reservations for i in r.get("Instances", [])]
    if len(instances) != 1:
        raise CollectError("EC2-B 인스턴스를 찾지 못함")
    inst = instances[0]
    launch = parse_time(inst["LaunchTime"])
    tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}

    start = launch.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ids = run(
        [
            "deploy",
            "list-deployments",
            "--application-name",
            app,
            "--deployment-group-name",
            group,
            "--create-time-range",
            f"start={start}",
        ]
    ).get("deployments", [])

    infos: list[dict] = []
    for chunk in _chunks(ids, 25):  # batch-get-deployments 한 번에 25건까지
        infos += run(["deploy", "batch-get-deployments", "--deployment-ids", *chunk]).get("deploymentsInfo", [])
    infos.sort(key=lambda x: parse_time(x["createTime"]))

    deployments: list[Deployment] = []
    for i, info in enumerate(infos):
        is_latest = i == len(infos) - 1
        # EC2-B 대상 상태는 판정에 쓰는 가장 최근 배포만 조회함
        ec2b_status = _ec2b_target_status(run, info["deploymentId"], ec2b) if is_latest else None
        deployments.append(Deployment(parse_time(info["createTime"]), info.get("status", ""), ec2b_status))

    health = run(["elbv2", "describe-target-health", "--target-group-arn", tg]).get("TargetHealthDescriptions", [])
    registered = any(h.get("Target", {}).get("Id") == ec2b for h in health)

    return Facts(inst["State"]["Name"], launch, tags, deployments, registered)


def _ec2b_target_status(run: Runner, deployment_id: str, ec2b: str) -> str | None:
    target_ids = run(["deploy", "list-deployment-targets", "--deployment-id", deployment_id]).get("targetIds", [])
    if ec2b not in target_ids:
        return None
    target = run(["deploy", "get-deployment-target", "--deployment-id", deployment_id, "--target-id", ec2b])
    return target.get("deploymentTarget", {}).get("instanceTarget", {}).get("status")


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        facts = collect()
    except (CollectError, KeyError, ValueError) as exc:
        reason = str(exc) if isinstance(exc, CollectError) else f"응답 형식 오류({type(exc).__name__})"
        print(f"#### EC2-B 재배포 순서 게이트: ❌ 조회 실패\n\n{reason}")
        return 2
    violations = evaluate(facts)
    print(render(violations))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
