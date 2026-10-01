"""scripts/plan_gate.py 고정 입력 검사 (STA-07-01~03).

보호 자원마다 일부러 교체·삭제를 일으킨 plan에서 게이트가 실패하는지, 그 외 변경은 통과하는지 확인한다.
공개 저장소 검사에 걸리지 않도록 식별자·값 표본은 코드에서 조립한다.
"""

import json

import pytest

from scripts import plan_gate

# 명세(STA-07-01) 기준 보호 자원 목록. 구현의 PROTECTED_TYPES에서 빠지면 테스트가 실패해야 함
REQUIRED_PROTECTED = [
    "aws_db_instance",  # RDS
    "aws_instance",  # EC2
    "aws_eip",  # EIP
    "aws_eip_association",  # EIP 연결
    "aws_cloudfront_distribution",  # CloudFront
    "aws_route53_record",  # Route53 레코드
    "aws_route53_zone",  # Route53 영역
    "aws_s3_bucket",  # S3
]
OPEN4 = ".".join(["0"] * 4) + "/0"
OPEN6 = "::/0"
VAL = "hidden-" + "v" * 8


def rc(rtype, actions, after=None, before=None, name="x", mode="managed", after_unknown=None):
    return {
        "address": f"module.g.{rtype}.{name}",
        "mode": mode,
        "type": rtype,
        "name": name,
        "change": {
            "actions": actions,
            "before": before,
            "after": after if after is not None else {},
            "after_unknown": after_unknown or {},
        },
    }


def plan(*changes, outputs=None):
    return {"resource_changes": list(changes), "output_changes": outputs or {}}


def rules(violations):
    return [v.rule for v in violations]


# ------------------------------------------------------------ G1


@pytest.mark.parametrize("rtype", REQUIRED_PROTECTED)
@pytest.mark.parametrize("actions", [["delete"], ["delete", "create"], ["create", "delete"]])
def test_G1_protected_delete_or_replace_is_blocked(rtype, actions):
    assert rules(plan_gate.evaluate(plan(rc(rtype, actions)))) == ["G1"]


@pytest.mark.parametrize("rtype", REQUIRED_PROTECTED)
@pytest.mark.parametrize("actions", [["no-op"], ["update"], ["create"], ["read"]])
def test_G1_protected_other_actions_pass(rtype, actions):
    assert plan_gate.evaluate(plan(rc(rtype, actions))) == []


def test_G1_import_only_passes():
    change = rc("aws_instance", ["no-op"])
    change["change"]["importing"] = {"id": "placeholder"}
    assert plan_gate.evaluate(plan(change)) == []


def test_G1_unprotected_delete_passes():
    assert plan_gate.evaluate(plan(rc("aws_lb", ["delete"]), rc("aws_ec2_instance_state", ["delete"]))) == []


def test_G1_data_source_ignored():
    assert plan_gate.evaluate(plan(rc("aws_instance", ["delete"], mode="data"))) == []


# ------------------------------------------------------------ G2


def test_G2_rds_password_change_is_blocked():
    p = plan(rc("aws_db_instance", ["update"], before={"password": None}, after={"password": VAL}))
    assert rules(plan_gate.evaluate(p)) == ["G2"]


def test_G2_rds_password_unknown_is_blocked():
    p = plan(rc("aws_db_instance", ["update"], after={"password": None}, after_unknown={"password": True}))
    assert rules(plan_gate.evaluate(p)) == ["G2"]


def test_G2_rds_without_password_passes():
    p = plan(rc("aws_db_instance", ["update"], before={"multi_az": False}, after={"multi_az": True, "password": None}))
    assert plan_gate.evaluate(p) == []


def test_G2_securestring_value_is_blocked():
    p = plan(rc("aws_ssm_parameter", ["create"], after={"type": "SecureString", "value": VAL}))
    assert rules(plan_gate.evaluate(p)) == ["G2"]


def test_G2_securestring_write_only_passes():
    p = plan(rc("aws_ssm_parameter", ["create"], after={"type": "SecureString", "value": None, "value_wo_version": 1}))
    assert plan_gate.evaluate(p) == []


def test_G2_plain_string_parameter_passes():
    p = plan(rc("aws_ssm_parameter", ["create"], after={"type": "String", "value": "ap-northeast-2"}))
    assert plan_gate.evaluate(p) == []


def test_G2_secrets_manager_value_is_blocked():
    p = plan(rc("aws_secretsmanager_secret_version", ["create"], after={"secret_string": VAL}))
    assert rules(plan_gate.evaluate(p)) == ["G2"]


def test_G2_sensitive_output_is_blocked():
    p = plan(outputs={"db": {"actions": ["create"], "after": VAL, "after_sensitive": True}})
    assert rules(plan_gate.evaluate(p)) == ["G2"]


def test_G2_plain_output_passes():
    p = plan(outputs={"db": {"actions": ["create"], "after": "name", "after_sensitive": False}})
    assert plan_gate.evaluate(p) == []


# ------------------------------------------------------------ G3


@pytest.mark.parametrize(
    "after",
    [
        {"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 22, "to_port": 22},
        {"cidr_ipv6": OPEN6, "ip_protocol": "tcp", "from_port": 3306, "to_port": 3306},
        {"cidr_ipv4": OPEN4, "ip_protocol": "-1", "from_port": None, "to_port": None},
        {"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 80, "to_port": 8080},
    ],
)
def test_G3_open_ingress_rule_is_blocked(after):
    assert rules(plan_gate.evaluate(plan(rc("aws_vpc_security_group_ingress_rule", ["create"], after=after)))) == ["G3"]


@pytest.mark.parametrize(
    "after",
    [
        {"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 443, "to_port": 443},
        {"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 80, "to_port": 80},
        {"cidr_ipv4": "10.0.0.0/16", "ip_protocol": "tcp", "from_port": 22, "to_port": 22},
        {"referenced_security_group_id": "placeholder", "ip_protocol": "tcp", "from_port": 8080, "to_port": 8080},
        {"cidr_ipv4": OPEN4, "ip_protocol": "icmp", "from_port": -1, "to_port": -1},
    ],
)
def test_G3_allowed_ingress_rule_passes(after):
    assert plan_gate.evaluate(plan(rc("aws_vpc_security_group_ingress_rule", ["create"], after=after))) == []


def test_G3_open_egress_passes():
    after = {"cidr_ipv4": OPEN4, "ip_protocol": "-1"}
    assert plan_gate.evaluate(plan(rc("aws_vpc_security_group_egress_rule", ["create"], after=after))) == []


def test_G3_existing_rule_import_passes():
    after = {"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 22, "to_port": 22}
    assert plan_gate.evaluate(plan(rc("aws_vpc_security_group_ingress_rule", ["no-op"], after=after))) == []


def test_G3_legacy_rule_and_inline_block_are_checked():
    legacy = rc("aws_security_group_rule", ["create"], after={"type": "ingress", "cidr_blocks": [OPEN4], "protocol": "tcp", "from_port": 22, "to_port": 22})
    inline = rc("aws_security_group", ["update"], after={"ingress": [{"cidr_blocks": [], "ipv6_cidr_blocks": [OPEN6], "protocol": "tcp", "from_port": 5432, "to_port": 5432}]})
    legacy_egress = rc("aws_security_group_rule", ["create"], after={"type": "egress", "cidr_blocks": [OPEN4], "protocol": "-1", "from_port": 0, "to_port": 0})
    assert rules(plan_gate.evaluate(plan(legacy, inline, legacy_egress))) == ["G3", "G3"]


def test_G3_only_security_group_is_blocked_in_mixed_plan():
    bad = rc("aws_vpc_security_group_ingress_rule", ["create"], after={"cidr_ipv4": OPEN4, "ip_protocol": "tcp", "from_port": 22, "to_port": 22})
    others = [rc("aws_s3_bucket", ["update"]), rc("aws_lb", ["create"]), rc("aws_instance", ["update"])]
    violations = plan_gate.evaluate(plan(bad, *others))
    assert [(v.rule, v.address) for v in violations] == [("G3", bad["address"])]


# ------------------------------------------------------------ 출력·CLI


def test_render_has_no_values():
    p = plan(
        rc("aws_db_instance", ["update"], after={"password": VAL}),
        rc("aws_ssm_parameter", ["create"], after={"type": "SecureString", "value": VAL}),
        outputs={"o": {"actions": ["create"], "after": VAL, "after_sensitive": True}},
    )
    out = plan_gate.render(plan_gate.evaluate(p))
    assert VAL not in out
    assert "차단 (3건)" in out


def test_render_redacts_identifiers_in_address():
    instance_id = "i-" + "0a" * 8 + "1"
    change = rc("aws_instance", ["delete"])
    change["address"] = f'module.compute.aws_instance.this["{instance_id}"]'
    out = plan_gate.render(plan_gate.evaluate(plan(change)))
    assert instance_id not in out
    assert "module.compute.aws_instance.this" in out


def test_cli_exit_codes(tmp_path, capsys):
    ok, bad, broken = tmp_path / "ok.json", tmp_path / "bad.json", tmp_path / "broken.json"
    ok.write_text(json.dumps(plan(rc("aws_s3_bucket", ["update"]))))
    bad.write_text(json.dumps(plan(rc("aws_s3_bucket", ["delete"]))))
    broken.write_text("{" + VAL)
    assert plan_gate.main(["plan_gate", str(ok)]) == 0
    assert plan_gate.main(["plan_gate", str(bad)]) == 1
    assert plan_gate.main(["plan_gate", str(broken)]) == 2
    assert VAL not in capsys.readouterr().out
