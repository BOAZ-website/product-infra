# deploy 모듈
# 담당 명세서: DEP (docs/wbs/27-dep.md) · 이슈: #63 DEP-01, #64 DEP-02
# 관리 자원: CodeDeploy 앱, 배포 그룹(`ec2_tag_set` app=boaz-api, AllAtOnce, 자동 롤백)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
#
# - 앱·배포 그룹은 prevent_destroy. 지워지면 backend cd.yml 배포가 바로 실패하기 때문
# - 번들 버킷은 두 자원 모두 참조하지 않음. backend cd.yml이 배포마다 지정함(decisions.md "DEP 선행 순서")

resource "aws_codedeploy_app" "this" {
  name             = var.application_name
  compute_platform = "Server"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_codedeploy_deployment_group" "this" {
  app_name              = aws_codedeploy_app.this.name
  deployment_group_name = var.deployment_group_name
  service_role_arn      = var.service_role_arn

  # 생략하면 기본값 OneAtATime이 들어가 plan에 변경이 생김. 실제 배포 방식(OneAtATime)은 cd.yml·season-up.sh가 배포마다 지정(DEP-02-02)
  deployment_config_name = "CodeDeployDefault.AllAtOnce"

  deployment_style {
    deployment_type   = "IN_PLACE"
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  # 최상위 ec2_tag_filter가 아니라 ec2_tag_set(DEP-01-02). 태그는 시즌 전환 스크립트가 EC2-B에 붙였다 뗌
  ec2_tag_set {
    ec2_tag_filter {
      key   = "app"
      type  = "KEY_AND_VALUE"
      value = "boaz-api"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
