# params 모듈
# 담당 명세서: IAM (docs/wbs/22-iam.md) · 이슈: #52 IAM-03
# 관리 자원: SSM 파라미터 `/boaz/infra/*` 12개(정확히 12개 검사). `/boaz/terraform/group-vars`는 관리하지 않음
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨

locals {
  path = "/boaz/infra"
}

# 개수·타입 검사용으로 경로 아래 실제 파라미터 이름·타입만 씀(검사는 root output, envs/prod/params.tf)
# - values는 코드에서 참조하지 않음(state에는 sensitive로 저장됨). with_decryption 기본값이 true라 false로 명시함
# - recursive: 하위 경로에 생긴 파라미터도 개수에 넣음
data "aws_ssm_parameters_by_path" "infra" {
  path            = local.path
  recursive       = true
  with_decryption = false
}

resource "aws_ssm_parameter" "infra" {
  for_each = var.names

  name = "${local.path}/${each.key}"
  type = "String"
  # 자리값임. 값은 Terraform이 바꾸지 않음(import한 실제 값 유지, ignore_changes)
  # - value는 필수 인자라 고정 문자열을 둠. sensitive 속성이라 plan 출력에 나오지 않음(insecure_value 쓰지 않음)
  # - STA-08(P7) 전에는 ignore_changes를 지우지 않음. 지우고 apply하면 자리값이 들어가 backend 시즌 전환 스크립트가 고장남
  # - STA-08에서 value를 관리 자원 속성으로 바꾸고 ignore_changes를 지움
  value = "managed-outside-terraform"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [value]

    # import 뒤 AWS에서 파라미터가 지워졌을 때 자리값으로 새로 만드는 plan을 막음(prevent_destroy는 생성을 막지 않음)
    precondition {
      condition     = contains(data.aws_ssm_parameters_by_path.infra.names, "${local.path}/${each.key}")
      error_message = "파라미터가 AWS에 없습니다. 자리값으로 새로 만들지 않도록 plan을 중단합니다."
    }
  }
}
