# deploy 그룹: CodeDeploy
# 담당 명세서: DEP (docs/wbs/27-dep.md)
#
# - 이 파일은 deploy 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "deploy" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/deploy/에 작성
# - import 블록은 imports_deploy.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

# 이름은 backend cd.yml에 이미 공개된 값. import id 조립에도 씀(imports_deploy.tf)
locals {
  deploy_names = {
    application      = "boaz-backend"
    deployment_group = "codedeploy-prod"
  }
}

module "deploy" {
  source = "../../modules/deploy"

  application_name      = local.deploy_names.application
  deployment_group_name = local.deploy_names.deployment_group
  service_role_arn      = module.iam.codedeploy_service_role_arn
}
