#!/usr/bin/env python3
"""PR plan CI용 plan 요약·로그 마스킹 도구 (STA-05).

공개 저장소라 Actions 로그·PR 코멘트는 누구나 볼 수 있다. plan 원문과
`terraform show -json` 결과에는 자원 ID·IP·sensitive 값이 평문으로 들어가므로
이 도구가 만든 요약만 밖으로 내보낸다.

  python3 scripts/plan_summary.py summary plan.json   # 마크다운 요약(값 없음, 주소·action만)
  python3 scripts/plan_summary.py redact < plan.log   # 오류 로그에서 계정 ID·자원 ID·IP 마스킹

외부 패키지 없이 표준 라이브러리만 사용한다.
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter

MASK = "<redacted>"
MAX_ADDRESSES = 50

# scripts/check-sensitive.sh와 같은 기준의 식별자 패턴
_REDACT_PATTERNS = [
    # 계정 ID가 들어간 ARN(ARN 전체)
    re.compile(r"arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:\d{12}:[^\s\"',)\]}]*"),
    # 공인 IP가 들어간 EC2 DNS
    re.compile(r"ec2-\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3}\.[A-Za-z0-9.-]+"),
    # AWS 자원 ID
    re.compile(
        r"\b(?:vpc|subnet|sg|sgr|igw|eigw|rtb|rtbassoc|acl|aclassoc|eipalloc|eipassoc|pl|i|ami|vol|snap"
        r"|eni|nat|vpce|tgw|tgw-attach|pcx|dopt|lt|cgw|vgw|vpn)-[0-9a-f]{8,17}\b"
    ),
    # CloudFront 배포 ID·Route53 영역 ID
    re.compile(r"\b(?=[A-Z0-9]*\d)(?:E[0-9A-Z]{11,13}|Z0[0-9A-Z]{10,20})\b"),
    # 액세스 키
    re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    # 계정 ID(12자리 숫자)
    re.compile(r"(?<!\d)\d{12}(?!\d)"),
    # IPv4 주소
    re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"),
]


def _env_literals() -> list[str]:
    """환경 변수 PLAN_SUMMARY_REDACT(줄바꿈 구분)의 값. CI가 state 버킷 이름 등 secret을 넘김."""
    raw = os.environ.get("PLAN_SUMMARY_REDACT", "")
    # 너무 짧은 값은 일반 단어를 지울 수 있어 제외
    return sorted({v.strip() for v in raw.splitlines() if len(v.strip()) >= 4}, key=len, reverse=True)


def redact(text: str, literals: list[str] | None = None) -> str:
    """식별자·IP와 지정한 문자열(literals, 기본값은 PLAN_SUMMARY_REDACT)을 MASK로 바꾼 문자열을 돌려준다."""
    for literal in _env_literals() if literals is None else literals:
        text = text.replace(literal, MASK)
    for pattern in _REDACT_PATTERNS:
        text = pattern.sub(MASK, text)
    return text


def classify(actions: list[str]) -> str:
    """resource_changes[].change.actions를 하나의 분류로 바꾼다."""
    # removed 블록(Terraform 1.7+): 자원은 남기고 state에서만 뺌. 관리 대상에서 빠지므로 따로 표시
    if "forget" in actions:
        return "forget"
    if "delete" in actions and "create" in actions:
        return "replace"
    if actions == ["delete"]:
        return "delete"
    if actions == ["create"]:
        return "create"
    if actions == ["update"]:
        return "update"
    if actions == ["read"]:
        return "read"
    return "no-op"


def summarize(plan: dict) -> dict:
    """plan JSON에서 값은 버리고 주소·action 분류·import 여부만 모은다."""
    counts: Counter[str] = Counter()
    changed: list[tuple[str, str]] = []
    imports = 0
    for rc in plan.get("resource_changes", []):
        change = rc.get("change", {})
        kind = classify(change.get("actions", []))
        if change.get("importing") is not None:
            imports += 1
        counts[kind] += 1
        if kind not in ("no-op", "read"):
            changed.append((kind, rc.get("address", "?")))
    output_changes = sum(
        1 for oc in plan.get("output_changes", {}).values() if oc.get("actions") != ["no-op"]
    )
    return {
        "counts": counts,
        "changed": changed,
        "imports": imports,
        "output_changes": output_changes,
    }


def render(result: dict) -> str:
    counts = result["counts"]
    lines = [
        "| import | create | update | replace | delete | forget | output 변경 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        "| {imp} | {c} | {u} | {r} | {d} | {f} | {o} |".format(
            imp=result["imports"],
            c=counts["create"],
            u=counts["update"],
            r=counts["replace"],
            d=counts["delete"],
            f=counts["forget"],
            o=result["output_changes"],
        ),
    ]
    changed = result["changed"]
    if changed:
        lines += ["", "변경 대상(값은 표시하지 않음):", ""]
        for kind, address in changed[:MAX_ADDRESSES]:
            lines.append(f"- `{kind}` {redact(address)}")
        if len(changed) > MAX_ADDRESSES:
            lines.append(f"- 외 {len(changed) - MAX_ADDRESSES}건")
    if counts["replace"] or counts["delete"]:
        lines += ["", "⚠️ 교체·삭제가 있습니다. 보호 자원이면 apply하지 않습니다(안전 게이트 STA-07)."]
    if counts["forget"]:
        lines += ["", "⚠️ state에서 빼는(forget) 자원이 있습니다. 자원은 남지만 Terraform 관리에서 빠집니다."]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "summary":
        with open(argv[2], encoding="utf-8") as f:
            plan = json.load(f)
        print(render(summarize(plan)))
        return 0
    if len(argv) == 2 and argv[1] == "redact":
        sys.stdout.write(redact(sys.stdin.read()))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
