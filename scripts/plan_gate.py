#!/usr/bin/env python3
"""plan 안전 게이트 (STA-07, design.md P1·P6, docs/wbs/11-sta.md "안전 게이트").

`terraform show -json plan.bin` 결과를 읽어 다음이 있으면 실패(exit 1)한다.

  G1 보호 자원 삭제·교체: RDS·EC2·EIP와 연결·CloudFront·Route53 레코드·영역·S3 버킷    (STA-07-01, P1)
  G2 시크릿 노출: RDS 비밀번호 변경, 시크릿 값을 state에 저장하는 설정, sensitive output  (STA-07-02, P6)
  G3 과도한 보안 그룹 규칙: 0.0.0.0/0·::/0에서 80·443 외 포트를 여는 inbound 규칙 추가·변경 (STA-07-03)

그 외 변경(태그·설정 update, 신규 자원 create, import)은 통과시킨다. 판정은 plan 안의
값을 쓰지만, 출력에는 규칙·자원 주소·사유만 쓰고 값은 쓰지 않는다(공개 저장소, P6).

  python3 scripts/plan_gate.py plan.json   # 마크다운 결과 출력, 위반 있으면 exit 1, 입력 오류 exit 2

외부 패키지 없이 표준 라이브러리만 사용한다.
"""

from __future__ import annotations

import ipaddress
import json
import sys
from dataclasses import dataclass
from typing import Any, Iterable

try:  # CI·로컬: python3 scripts/plan_gate.py / pytest: from scripts import plan_gate
    from plan_summary import redact
except ImportError:  # pragma: no cover
    from scripts.plan_summary import redact

# G1: 삭제·교체되면 서비스 중단이나 데이터 손실이 나는 자원(design.md Protected_Resource)
PROTECTED_TYPES = frozenset(
    {
        "aws_db_instance",
        "aws_instance",
        "aws_eip",
        "aws_eip_association",
        "aws_cloudfront_distribution",
        "aws_route53_record",
        "aws_route53_zone",
        "aws_s3_bucket",
    }
)

# G3: 전체 인터넷에 열어도 되는 포트(HTTP·HTTPS)
PUBLIC_ALLOWED_PORTS = frozenset({80, 443})


@dataclass(frozen=True)
class Violation:
    rule: str
    address: str
    reason: str

    def render(self) -> str:
        return f"- `{self.rule}` {redact(self.address)}: {self.reason}"


def _actions(rc: dict) -> list[str]:
    return list(rc.get("change", {}).get("actions", []))


def _changes_config(actions: list[str]) -> bool:
    """이번 plan이 자원 설정을 새로 쓰는지(create·update·replace). import-only no-op은 아님."""
    return any(a in ("create", "update") for a in actions)


def _after(rc: dict) -> dict:
    after = rc.get("change", {}).get("after")
    return after if isinstance(after, dict) else {}


def _before(rc: dict) -> dict:
    before = rc.get("change", {}).get("before")
    return before if isinstance(before, dict) else {}


def _after_unknown(rc: dict) -> dict:
    unknown = rc.get("change", {}).get("after_unknown")
    return unknown if isinstance(unknown, dict) else {}


def _managed(plan: dict) -> Iterable[dict]:
    for rc in plan.get("resource_changes", []) or []:
        if isinstance(rc, dict) and rc.get("mode", "managed") == "managed":
            yield rc


# ---------------------------------------------------------------- G1 보호 자원


def check_protected(plan: dict) -> list[Violation]:
    out = []
    for rc in _managed(plan):
        if rc.get("type") not in PROTECTED_TYPES:
            continue
        actions = _actions(rc)
        if "delete" in actions:
            kind = "교체" if "create" in actions else "삭제"
            out.append(Violation("G1", rc.get("address", "?"), f"보호 자원 {kind} 계획"))
    return out


# ---------------------------------------------------------------- G2 시크릿


def _set_value(value: Any) -> bool:
    return value not in (None, "", [], {})


def check_secrets(plan: dict) -> list[Violation]:
    out = []
    for rc in _managed(plan):
        actions = _actions(rc)
        if not _changes_config(actions):
            continue
        rtype, address = rc.get("type"), rc.get("address", "?")
        after, before, unknown = _after(rc), _before(rc), _after_unknown(rc)

        if rtype in ("aws_db_instance", "aws_rds_cluster"):
            for attr in ("password", "master_password"):
                if unknown.get(attr) is True or (
                    _set_value(after.get(attr)) and after.get(attr) != before.get(attr)
                ):
                    out.append(Violation("G2", address, "RDS 비밀번호가 plan에서 설정·변경됨(ignore_changes = [password] 필요)"))
                    break

        elif rtype == "aws_ssm_parameter":
            if after.get("type") == "SecureString" and (
                _set_value(after.get("value")) or _set_value(after.get("insecure_value"))
            ):
                out.append(Violation("G2", address, "SecureString 값이 state에 저장되는 설정(value_wo 사용)"))

        elif rtype == "aws_secretsmanager_secret_version":
            if _set_value(after.get("secret_string")) or _set_value(after.get("secret_binary")):
                out.append(Violation("G2", address, "시크릿 값이 state에 저장되는 설정(secret_string_wo 사용)"))

    for name, oc in (plan.get("output_changes", {}) or {}).items():
        if not isinstance(oc, dict) or oc.get("actions") in (["no-op"], ["delete"]):
            continue
        if oc.get("after_sensitive") and _set_value(oc.get("after")):
            out.append(Violation("G2", f"output.{name}", "sensitive output 값이 plan·state에 기록됨"))
    return out


# ---------------------------------------------------------------- G3 보안 그룹


def _is_open(cidr: Any) -> bool:
    if not isinstance(cidr, str) or not cidr:
        return False
    try:
        return ipaddress.ip_network(cidr, strict=False).prefixlen == 0
    except ValueError:
        return False


def _exposes_disallowed_port(protocol: Any, from_port: Any, to_port: Any) -> bool:
    """전체 공개 시 80·443 외 포트가 열리는지. 프로토콜 전체(-1)·포트 범위도 위반."""
    if str(protocol) in ("-1", "all"):
        return True
    if str(protocol).lower() in ("icmp", "icmpv6", "1", "58"):
        return False
    try:
        low, high = int(from_port), int(to_port)
    except (TypeError, ValueError):
        return True  # 알 수 없으면 차단 쪽으로 판정
    if high < low:
        low, high = high, low
    return any(port not in PUBLIC_ALLOWED_PORTS for port in range(low, min(high, 65535) + 1))


def _rules_of(rc: dict) -> list[tuple[list, Any, Any, Any]]:
    """(cidr 목록, protocol, from, to) 목록. inbound 규칙만."""
    rtype, after = rc.get("type"), _after(rc)
    if rtype == "aws_vpc_security_group_ingress_rule":
        return [([after.get("cidr_ipv4"), after.get("cidr_ipv6")], after.get("ip_protocol"), after.get("from_port"), after.get("to_port"))]
    if rtype == "aws_security_group_rule" and after.get("type") == "ingress":
        cidrs = list(after.get("cidr_blocks") or []) + list(after.get("ipv6_cidr_blocks") or [])
        return [(cidrs, after.get("protocol"), after.get("from_port"), after.get("to_port"))]
    if rtype == "aws_security_group":
        rules = []
        for block in after.get("ingress") or []:
            if isinstance(block, dict):
                cidrs = list(block.get("cidr_blocks") or []) + list(block.get("ipv6_cidr_blocks") or [])
                rules.append((cidrs, block.get("protocol"), block.get("from_port"), block.get("to_port")))
        return rules
    return []


def check_security_groups(plan: dict) -> list[Violation]:
    out = []
    for rc in _managed(plan):
        if not _changes_config(_actions(rc)):
            continue  # import-only·삭제는 이 규칙 대상 아님(현행 규칙 편입은 통과)
        for cidrs, protocol, from_port, to_port in _rules_of(rc):
            if any(_is_open(c) for c in cidrs) and _exposes_disallowed_port(protocol, from_port, to_port):
                out.append(Violation("G3", rc.get("address", "?"), "0.0.0.0/0·::/0에 80·443 외 포트를 여는 inbound 규칙"))
                break
    return out


# ---------------------------------------------------------------- 실행


def evaluate(plan: dict) -> list[Violation]:
    if not isinstance(plan, dict):
        raise ValueError("plan JSON 최상위가 객체가 아님")
    return check_protected(plan) + check_secrets(plan) + check_security_groups(plan)


def render(violations: list[Violation]) -> str:
    if not violations:
        return "#### 안전 게이트: ✅ 통과\n\n보호 자원 삭제·교체, 시크릿 노출, 과도한 보안 그룹 규칙 없음"
    lines = [f"#### 안전 게이트: ❌ 차단 ({len(violations)}건)", ""]
    lines += [v.render() for v in violations]
    lines += ["", "규칙: G1 보호 자원 삭제·교체, G2 시크릿 노출, G3 과도한 보안 그룹 규칙. apply하지 않습니다."]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            violations = evaluate(json.load(f))
    except (OSError, ValueError) as exc:
        # 예외 메시지에 plan 값이 섞일 수 있어 종류만 출력
        print(f"#### 안전 게이트: ❌ plan JSON을 읽지 못함({type(exc).__name__})")
        return 2
    print(render(violations))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
