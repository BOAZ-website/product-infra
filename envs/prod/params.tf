# params 그룹: SSM 파라미터
# 담당 명세서: IAM (docs/wbs/22-iam.md)
#
# - 이 파일은 params 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "params" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/params/에 작성
# - import 블록은 imports_params.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

# 관리 대상 이름(import for_each와 모듈 입력이 함께 씀). 이름은 공개 문서(docs/records/inventory.md 12절)에 이미 있는 값
locals {
  params_infra_names = toset([
    "ALB_PORT",
    "ALB_SG_ID",
    "ALB_SUBNETS",
    "CLOUDFRONT_DIST_ID",
    "CODEDEPLOY_APP",
    "CODEDEPLOY_GROUP",
    "EC2_A_DOMAIN",
    "EC2_A_PORT",
    "EC2_B_ID",
    "RDS_IDENTIFIER",
    "S3_BUCKET",
    "TARGET_GROUP_ARN",
  ])
}

# 경로 조회 결과 중 String인 짧은 이름(imports_params.tf가 사용)
locals {
  params_infra_string_names = toset([
    for i, n in module.params.existing_names : trimprefix(n, "/boaz/infra/")
    if module.params.existing_types[i] == "String"
  ])
}

module "params" {
  source = "../../modules/params"

  names = local.params_infra_names
}

# IAM-03-01: `/boaz/infra` 아래는 관리 대상 12개와 정확히 같고 모두 String이어야 함. 다르면 plan 실패
# - check 블록은 경고만 내므로 쓰지 않음. 모듈 안 data postcondition은 테스트의 expect_failures로 지정할 수 없어 root output에 둠
# - 값은 참조하지 않음. 출력은 개수(숫자)뿐
output "params_infra_count" {
  description = "`/boaz/infra` 아래 파라미터 개수(검사 통과 시 12)"
  value       = length(module.params.existing_names)

  precondition {
    condition     = toset(module.params.existing_names) == toset([for n in local.params_infra_names : "/boaz/infra/${n}"])
    error_message = "`/boaz/infra` 아래 파라미터 이름이 관리 대상 12개와 다릅니다. 추가·누락된 이름을 확인하세요."
  }
  precondition {
    condition     = alltrue([for t in module.params.existing_types : t == "String"])
    error_message = "`/boaz/infra` 아래에 String이 아닌 파라미터가 있습니다. SecureString 값이 state에 들어가지 않도록 plan을 중단합니다."
  }
}
