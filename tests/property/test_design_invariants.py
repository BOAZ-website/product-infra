"""설계 Property 테스트 (design.md "Correctness Properties", "PBT 적용성 판단").

설계 Property마다 property-based test 하나를 둔다. 테스트 이름에 Property 번호를 넣어
`pytest -k P1`처럼 골라 실행한다. AWS에 요청하지 않고 합성 plan JSON만 다룬다.
결정 "property 테스트 범위"(대기)는 권장안(hypothesis는 P1·P6만)으로 진행 중이다.
"""

import json

from hypothesis import given
from hypothesis import strategies as st

from scripts import plan_gate, plan_summary

UNPROTECTED_TYPES = ["aws_lb", "aws_lb_listener", "aws_lb_target_group", "aws_ec2_instance_state", "aws_iam_role", "aws_ssm_parameter", "aws_codedeploy_app"]
ACTIONS = [["no-op"], ["create"], ["update"], ["read"], ["delete"], ["delete", "create"], ["create", "delete"]]

resource_change = st.builds(
    lambda rtype, actions, name, importing: {
        "address": f"module.g.{rtype}.{name}",
        "mode": "managed",
        "type": rtype,
        "name": name,
        "change": {"actions": actions, "before": {}, "after": {}, "after_unknown": {}, **({"importing": {"id": "x"}} if importing else {})},
    },
    rtype=st.sampled_from(sorted(plan_gate.PROTECTED_TYPES) + UNPROTECTED_TYPES),
    actions=st.sampled_from(ACTIONS),
    name=st.from_regex(r"[a-z][a-z0-9_]{0,15}", fullmatch=True),
    importing=st.booleans(),
)


@given(st.lists(resource_change, max_size=30))
def test_P1_protected_resources_are_never_deleted_or_replaced(changes):
    """Feature: product-infra-migration, Property 1: 보호 자원 무교체 불변식.

    For any plan, the gate SHALL pass only if no protected resource (RDS·EC2·EIP·EIP 연결·CloudFront·
    Route53 레코드·영역·S3 버킷) has a delete or replace action, and SHALL report every such resource.
    """
    expected = sorted(
        c["address"] for c in changes if c["type"] in plan_gate.PROTECTED_TYPES and "delete" in c["change"]["actions"]
    )
    violations = plan_gate.check_protected({"resource_changes": changes})
    assert sorted(v.address for v in violations) == expected
    assert all(v.rule == "G1" for v in violations)
    assert (plan_gate.evaluate({"resource_changes": changes}) == []) == (expected == [])


# 시크릿 표본: 주소·규칙 문구와 겹치지 않도록 고정 접두어 + 임의 문자열
secret_value = st.text(alphabet=st.characters(codec="utf-8", exclude_categories=("Cs", "Cc")), min_size=8, max_size=40).map(
    lambda s: "SV9q" + s
)


def _secret_plan(secret, where):
    """시크릿 값을 plan 안의 여러 위치에 넣는다. 게이트는 G2로 막아야 하고, 어떤 출력에도 값이 없어야 함."""
    rcs = {
        "rds": {"type": "aws_db_instance", "change": {"actions": ["update"], "before": {"password": None}, "after": {"password": secret}}},
        "ssm": {"type": "aws_ssm_parameter", "change": {"actions": ["create"], "before": None, "after": {"type": "SecureString", "value": secret}}},
        "sm": {"type": "aws_secretsmanager_secret_version", "change": {"actions": ["create"], "before": None, "after": {"secret_string": secret}}},
    }
    changes = []
    for key in where:
        body = rcs[key]
        changes.append({"address": f"module.g.{body['type']}.{key}", "mode": "managed", "name": key, **body})
    return {
        "resource_changes": changes,
        "output_changes": {"conn": {"actions": ["create"], "after": {"nested": [secret]}, "after_sensitive": True}},
    }


@given(secret_value, st.lists(st.sampled_from(["rds", "ssm", "sm"]), min_size=1, max_size=3, unique=True))
def test_P6_secret_values_never_appear_in_output(secret, where):
    """Feature: product-infra-migration, Property 6: 시크릿 비노출.

    For any secret value placed in a plan (RDS password, SecureString value, Secrets Manager value,
    sensitive output), the gate SHALL block it (G2) and neither the gate report, the plan summary,
    nor redacted logs SHALL contain the secret text.
    """
    p = _secret_plan(secret, where)
    violations = plan_gate.evaluate(p)
    assert len([v for v in violations if v.rule == "G2"]) == len(where) + 1

    outputs = [
        plan_gate.render(violations),
        plan_summary.render(plan_summary.summarize(p)),
        plan_summary.redact("Error: " + json.dumps({"address": "module.g.x"})),
    ]
    for text in outputs:
        assert secret not in text
