# iam 그룹 import 블록 전용 파일 (담당 명세서: IAM, docs/wbs/22-iam.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md

# - 롤·인스턴스 프로파일·인라인 정책은 이름 기반 import(이름은 공개 가능)
# - ARN이 필요한 import id는 계정 ID 변수로 조립함(계정 ID 리터럴 금지). 이름·키 목록은 iam.tf의 local.iam_import

import {
  to = module.iam.aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::${var.expected_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

import {
  for_each = local.iam_import.roles
  to       = module.iam.aws_iam_role.this[each.key]
  id       = each.value
}

import {
  for_each = local.iam_import.policies
  to       = module.iam.aws_iam_policy.this[each.key]
  id       = "${local.iam_import.policy_arn_prefix}${each.value}"
}

import {
  for_each = local.iam_import.role_policy_attachments
  to       = module.iam.aws_iam_role_policy_attachment.this[each.key]
  id       = "${local.iam_import.roles[each.value.role]}/${each.value.policy_arn}"
}

import {
  for_each = local.iam_import.role_policies
  to       = module.iam.aws_iam_role_policy.this[each.key]
  id       = "${local.iam_import.roles[each.value.role]}:${each.value.name}"
}

import {
  to = module.iam.aws_iam_instance_profile.ec2
  id = "role-prod-ec2"
}
