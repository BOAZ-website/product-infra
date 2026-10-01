"""scripts/plan_summary.py 검사 (STA-05). 표준 라이브러리 unittest만 사용.

  python3 -m unittest discover -s tests/static -v

공개 저장소 검사(check-sensitive.sh)에 걸리지 않도록 계정 ID·자원 ID·IP 표본은 코드에서 조립한다.
"""

import importlib.util
import os
import pathlib
import unittest

_ROOT = pathlib.Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("plan_summary", _ROOT / "scripts" / "plan_summary.py")
plan_summary = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(plan_summary)

ACCOUNT = "1" * 12
INSTANCE_ID = "i-" + "0a" * 8 + "1"
SG_ID = "sg-" + "0f" * 8
IP = ".".join(["203", "0", "113", "7"])
ARN = "arn:aws:iam::" + ACCOUNT + ":role/example"
DISTRIBUTION_ID = "E" + "2ABCDEF3GHIJ"
VAL = "hidden-" + "v" * 8  # plan 값 표본(요약에 나오면 안 됨)


def _rc(address, actions, importing=None, after=None):
    change = {"actions": actions, "before": None, "after": after or {}}
    if importing is not None:
        change["importing"] = importing
    return {"address": address, "change": change}


class RedactTest(unittest.TestCase):
    def test_masks_identifiers(self):
        text = f"error reading {INSTANCE_ID} in {SG_ID} from {IP} via {ARN} on {DISTRIBUTION_ID} acct {ACCOUNT}"
        out = plan_summary.redact(text)
        for raw in (INSTANCE_ID, SG_ID, IP, ARN, DISTRIBUTION_ID, ACCOUNT):
            self.assertNotIn(raw, out)
        self.assertIn("error reading", out)

    def test_masks_env_literals(self):
        bucket = "example-state-" + "bucket"
        os.environ["PLAN_SUMMARY_REDACT"] = f"{bucket}\n\nab\n"
        try:
            out = plan_summary.redact(f"Error: failed to read s3://{bucket}/key ab")
        finally:
            del os.environ["PLAN_SUMMARY_REDACT"]
        self.assertNotIn(bucket, out)
        self.assertIn(" ab", out)  # 4자 미만 값은 가리지 않음

    def test_keeps_plain_text(self):
        text = "Error: Invalid value for variable api_origin"
        self.assertEqual(plan_summary.redact(text), text)


class ClassifyTest(unittest.TestCase):
    def test_replace_both_orders(self):
        self.assertEqual(plan_summary.classify(["delete", "create"]), "replace")
        self.assertEqual(plan_summary.classify(["create", "delete"]), "replace")

    def test_forget_is_separate(self):
        self.assertEqual(plan_summary.classify(["forget"]), "forget")

    def test_single_actions(self):
        self.assertEqual(plan_summary.classify(["delete"]), "delete")
        self.assertEqual(plan_summary.classify(["create"]), "create")
        self.assertEqual(plan_summary.classify(["update"]), "update")
        self.assertEqual(plan_summary.classify(["no-op"]), "no-op")


class SummaryTest(unittest.TestCase):
    def setUp(self):
        self.plan = {
            "resource_changes": [
                _rc("module.network.aws_vpc.main", ["no-op"], importing={"id": "x"}),
                _rc("module.compute.aws_instance.ec2_b", ["delete", "create"], after={"password": VAL}),
                _rc("module.storage.aws_s3_bucket.app", ["update"], after={"tags": {"k": VAL}}),
                _rc("module.cdn.aws_route53_record.api", ["delete"]),
                _rc("module.params.aws_ssm_parameter.x", ["create"], after={"value": VAL}),
            ],
            "output_changes": {"a": {"actions": ["create"]}, "b": {"actions": ["no-op"]}},
        }

    def test_counts(self):
        result = plan_summary.summarize(self.plan)
        self.assertEqual(result["imports"], 1)
        self.assertEqual(result["counts"]["replace"], 1)
        self.assertEqual(result["counts"]["delete"], 1)
        self.assertEqual(result["counts"]["update"], 1)
        self.assertEqual(result["counts"]["create"], 1)
        self.assertEqual(result["output_changes"], 1)

    def test_render_has_no_values_and_warns(self):
        out = plan_summary.render(plan_summary.summarize(self.plan))
        self.assertNotIn(VAL, out)
        self.assertIn("module.compute.aws_instance.ec2_b", out)
        self.assertNotIn("module.network.aws_vpc.main", out)  # import-only no-op은 변경 목록에 없음
        self.assertIn("교체·삭제", out)

    def test_no_changes(self):
        out = plan_summary.render(plan_summary.summarize({"resource_changes": []}))
        self.assertIn("| 0 | 0 | 0 | 0 | 0 | 0 | 0 |", out)
        self.assertNotIn("교체·삭제", out)
        self.assertNotIn("forget", out.split("\n", 2)[2])

    def test_forget_is_listed_and_warned(self):
        plan = {"resource_changes": [_rc("module.compute.aws_instance.ec2_b", ["forget"])]}
        out = plan_summary.render(plan_summary.summarize(plan))
        self.assertIn("`forget` module.compute.aws_instance.ec2_b", out)
        self.assertIn("state에서 빼는(forget)", out)

    def test_address_is_redacted(self):
        plan = {"resource_changes": [_rc(f'module.x.aws_instance.y["{INSTANCE_ID}"]', ["update"])]}
        out = plan_summary.render(plan_summary.summarize(plan))
        self.assertNotIn(INSTANCE_ID, out)


if __name__ == "__main__":
    unittest.main()
