# iam 그룹: IAM 롤·정책·OIDC·인스턴스 프로파일
# 담당 명세서: IAM (docs/wbs/22-iam.md)
#
# - 이 파일은 iam 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "iam" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/iam/에 작성
# - import 블록은 imports_iam.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

module "iam" {
  source = "../../modules/iam"

  account_id = var.expected_account_id
  group_vars = local.group_vars.iam
}

# import id 조립용 이름·키 목록(imports_iam.tf가 사용)
# - 키는 modules/iam의 for_each 키와 같아야 함. 롤·정책 이름을 바꿀 때는 modules/iam/{main,policies}.tf와 함께 고침
locals {
  iam_policy_arn_prefix = "arn:aws:iam::${var.expected_account_id}:policy/"

  iam_import = {
    policy_arn_prefix = local.iam_policy_arn_prefix

    roles = {
      backend        = "role-prod-github-actions"
      frontend       = "role-prod-github-actions-frontend"
      frontend_admin = "role-prod-github-actions-frontend-admin"
      codedeploy     = "role-prod-codedeploy"
      ec2            = "role-prod-ec2"
    }
    policies = {
      frontend_deploy       = "boaz-prod-frontend-deploy"
      frontend_admin_deploy = "boaz-prod-frontend-admin-deploy"
      ec2_s3_archiving      = "boaz-ec2-s3-archiving-policy"
      ec2_s3_recruitment    = "boaz-ec2-s3-recruitment-policy"
    }
    # 키 → <롤 키>, <정책 ARN>. 고객 관리형은 계정 ID 변수로 조립, AWS 관리형은 고정 ARN
    role_policy_attachments = {
      frontend_frontend_deploy             = { role = "frontend", policy_arn = "${local.iam_policy_arn_prefix}boaz-prod-frontend-deploy" }
      frontend_admin_frontend_admin_deploy = { role = "frontend_admin", policy_arn = "${local.iam_policy_arn_prefix}boaz-prod-frontend-admin-deploy" }
      codedeploy_codedeploy_role           = { role = "codedeploy", policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole" }
      ec2_s3_archiving                     = { role = "ec2", policy_arn = "${local.iam_policy_arn_prefix}boaz-ec2-s3-archiving-policy" }
      ec2_s3_recruitment                   = { role = "ec2", policy_arn = "${local.iam_policy_arn_prefix}boaz-ec2-s3-recruitment-policy" }
      ec2_cloudwatch_agent                 = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
      ec2_ssm_core                         = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
      ec2_s3_readonly                      = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" }
    }
    # 키 → <롤 키>, <인라인 정책 이름>
    role_policies = {
      backend_github_action_deploy = { role = "backend", name = "boaz-github-action-deploy" }
      ec2_codedeploy_read          = { role = "ec2", name = "boaz-codedeploy-read" }
      ec2_ssm_read                 = { role = "ec2", name = "boaz-ssm-read" }
      ec2_cloudwatch_list_metric   = { role = "ec2", name = "cloudwatch-list-metric" }
    }
  }
}
