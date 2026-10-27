# 시즌 변수·상태 모델 검사 (SEA-01). AWS에 요청하지 않음(mock provider, backend 미사용)
#   terraform -chdir=envs/prod init -backend=false
#   terraform -chdir=envs/prod test

mock_provider "aws" {
  # 그룹 값 파라미터(locals.tf)를 가짜 JSON 객체로 대체함. 키 규칙·그룹별 키 표: docs/guides/import-procedure.md 1-1-1절
  # - 그룹 담당은 자기 그룹 키를 아래 jsonencode 안에 같은 PR에서 추가함. 값은 실제 ID 형식을 흉내 내지 않고 fake- 로 시작하는 문자열을 씀
  # - import 블록이 있는 그룹은 import 대상 자원마다 아래에 override_resource를 추가함(mock provider는 import를 지원하지 않음)
  override_data {
    target = data.aws_ssm_parameter.group_vars
    values = {
      type = "String"
      insecure_value = jsonencode({
        # <그룹> = { <키> = <값> }
        iam = { distribution_ids = { www = "fake-www", dev = "fake-dev", admin = "fake-admin" } }
        network = {
          vpc_id                 = "fake-vpc"
          internet_gateway_id    = "fake-igw"
          default_network_acl_id = "fake-acl"
          public_subnet_ids      = { a = "fake-public-a", c = "fake-public-c" }
          private_subnet_ids     = { a = "fake-private-a", c = "fake-private-c" }
          route_table_ids        = { public = "fake-rtb-public", private = "fake-rtb-private" }
          security_group_ids = {
            alb = "fake-sg-alb", alb_to_ec2 = "fake-sg-alb-to-ec2", cf_to_ec2 = "fake-sg-cf-to-ec2",
            rds = "fake-sg-rds", ec2_to_rds = "fake-sg-ec2-to-rds", ssh = "fake-sg-ssh",
          }
          ingress_rule_ids = { alb = "fake-in-alb", alb_to_ec2 = "fake-in-alb-to-ec2", cf_to_ec2 = "fake-in-cf-to-ec2", rds = "fake-in-rds" }
          egress_rule_ids = {
            alb = "fake-out-alb", alb_to_ec2 = "fake-out-alb-to-ec2", cf_to_ec2 = "fake-out-cf-to-ec2",
            rds = "fake-out-rds", ec2_to_rds = "fake-out-ec2-to-rds", ssh = "fake-out-ssh",
          }
          ssh_rule_ids = { ops_1 = "fake-ssh-ops-1" }
          # CIDR 형식이 필요해 사설 대역 값을 씀(공인 IP 금지)
          ssh_allowed_cidrs = { ops_1 = "10.255.0.1/32" }
        }
      })
    }
  }

  # 그룹별 override_resource 구역(그룹마다 한 블록. target은 module.<그룹>.<자원 주소>)

  # network
  override_resource {
    target = module.network.aws_vpc.main
  }
  override_resource {
    target = module.network.aws_subnet.public
  }
  override_resource {
    target = module.network.aws_subnet.private
  }
  override_resource {
    target = module.network.aws_internet_gateway.main
  }
  override_resource {
    target = module.network.aws_default_route_table.main
  }
  override_resource {
    target = module.network.aws_route_table.public
  }
  override_resource {
    target = module.network.aws_route_table.private
  }
  override_resource {
    target = module.network.aws_route.public_internet
  }
  override_resource {
    target = module.network.aws_route_table_association.public
  }
  override_resource {
    target = module.network.aws_route_table_association.private
  }
  override_resource {
    target = module.network.aws_default_network_acl.main
  }
  override_resource {
    target = module.network.aws_security_group.main
  }
  override_resource {
    target = module.network.aws_vpc_security_group_ingress_rule.main
  }
  override_resource {
    target = module.network.aws_vpc_security_group_egress_rule.main
  }
  override_resource {
    target = module.network.aws_vpc_security_group_ingress_rule.ssh
  }

  # iam
  override_resource {
    target = module.iam.aws_iam_openid_connect_provider.github
  }
  override_resource {
    target = module.iam.aws_iam_role.this
    # deploy 배포 그룹 service_role_arn 형식 검사를 통과하는 가짜 ARN(계정 ID 없음)
    values = {
      arn = "arn:aws:iam::aws:role/fake-role"
    }
  }
  override_resource {
    target = module.iam.aws_iam_policy.this
    # 정책 연결의 policy_arn 형식 검사를 통과하는 가짜 ARN(계정 ID 없음)
    values = {
      arn = "arn:aws:iam::aws:policy/fake-policy"
    }
  }
  override_resource {
    target = module.iam.aws_iam_role_policy_attachment.this
  }
  override_resource {
    target = module.iam.aws_iam_role_policy.this
  }
  override_resource {
    target = module.iam.aws_iam_instance_profile.ec2
  }

  # deploy
  override_resource {
    target = module.deploy.aws_codedeploy_app.this
  }
  override_resource {
    target = module.deploy.aws_codedeploy_deployment_group.this
  }

  # params: 경로 조회 결과를 관리 대상 12개(모두 String)로 대체함. 이름 목록은 envs/prod/params.tf와 같게 유지
  override_data {
    target = module.params.data.aws_ssm_parameters_by_path.infra
    values = {
      names = [
        "/boaz/infra/ALB_PORT", "/boaz/infra/ALB_SG_ID", "/boaz/infra/ALB_SUBNETS", "/boaz/infra/CLOUDFRONT_DIST_ID",
        "/boaz/infra/CODEDEPLOY_APP", "/boaz/infra/CODEDEPLOY_GROUP", "/boaz/infra/EC2_A_DOMAIN", "/boaz/infra/EC2_A_PORT",
        "/boaz/infra/EC2_B_ID", "/boaz/infra/RDS_IDENTIFIER", "/boaz/infra/S3_BUCKET", "/boaz/infra/TARGET_GROUP_ARN",
      ]
      types = [for i in range(12) : "String"]
    }
  }
  override_resource {
    target = module.params.aws_ssm_parameter.infra
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  # 형식 검사만 통과하는 가짜 계정 ID(공개 저장소 규칙상 12자리 숫자를 직접 적지 않음)
  expected_account_id = format("%012d", 0)
}

run "off_ec2_is_offseason" {
  command = plan

  variables {
    season_capacity = "off"
    api_origin      = "ec2"
  }

  assert {
    condition     = local.season.alb_enabled == false && local.season.ec2_b_state == "stopped"
    error_message = "평시에는 ALB가 없고 EC2-B가 중지 상태여야 합니다."
  }
  assert {
    condition     = length(local.season.ec2_b_functional_tags) == 0
    error_message = "평시에는 EC2-B에 기능 태그가 없어야 합니다."
  }
  assert {
    condition     = local.season.target_keys == ["ec2_a"] && local.season.rds_multi_az == false
    error_message = "평시 Target Group 대상은 EC2-A뿐이고 RDS는 단일 AZ여야 합니다."
  }
  assert {
    condition     = local.season.api_origin.target == "ec2_a" && local.season.api_origin.port == 8080
    error_message = "api_origin = ec2이면 origin은 EC2-A:8080이어야 합니다."
  }
  assert {
    condition     = can(keys(local.group_vars))
    error_message = "그룹 값 파라미터의 JSON이 객체로 읽혀야 합니다."
  }
}

run "on_ec2_is_transition" {
  command = plan

  variables {
    season_capacity = "on"
    api_origin      = "ec2"
  }

  assert {
    condition     = local.season.alb_enabled && local.season.ec2_b_state == "running" && local.season.ec2_b_functional_tags == { app = "boaz-api" }
    error_message = "season_capacity = on이면 ALB가 있고 EC2-B가 app = boaz-api 태그로 기동돼야 합니다."
  }
  assert {
    condition     = local.season.target_keys == ["ec2_a", "ec2_b"] && local.season.rds_multi_az
    error_message = "season_capacity = on이면 Target Group 대상이 EC2-A·EC2-B이고 RDS는 Multi-AZ여야 합니다."
  }
  assert {
    condition     = local.season.api_origin.target == "ec2_a" && local.season.api_origin.port == 8080
    error_message = "전환 중(on + ec2)에는 origin이 아직 EC2-A:8080이어야 합니다."
  }
}

run "on_alb_is_season" {
  command = plan

  variables {
    season_capacity = "on"
    api_origin      = "alb"
  }

  assert {
    condition     = local.season.alb_enabled && local.season.rds_multi_az
    error_message = "모집 시즌에는 ALB가 있고 RDS가 Multi-AZ여야 합니다."
  }
  assert {
    condition     = local.season.api_origin.target == "alb" && local.season.api_origin.port == 80
    error_message = "api_origin = alb이면 origin은 ALB:80이어야 합니다."
  }
}

run "off_alb_is_rejected" {
  command = plan

  variables {
    season_capacity = "off"
    api_origin      = "alb"
  }

  expect_failures = [var.api_origin]
}

run "invalid_capacity_is_rejected" {
  command = plan

  variables {
    season_capacity = "On"
    api_origin      = "ec2"
  }

  expect_failures = [var.season_capacity]
}

run "invalid_origin_is_rejected" {
  command = plan

  variables {
    season_capacity = "on"
    api_origin      = "cloudfront"
  }

  expect_failures = [var.api_origin]
}

run "params_extra_parameter_is_rejected" {
  command = plan

  variables {
    season_capacity = "off"
    api_origin      = "ec2"
  }

  override_data {
    target = module.params.data.aws_ssm_parameters_by_path.infra
    values = {
      names = [
        "/boaz/infra/ALB_PORT", "/boaz/infra/ALB_SG_ID", "/boaz/infra/ALB_SUBNETS", "/boaz/infra/CLOUDFRONT_DIST_ID",
        "/boaz/infra/CODEDEPLOY_APP", "/boaz/infra/CODEDEPLOY_GROUP", "/boaz/infra/EC2_A_DOMAIN", "/boaz/infra/EC2_A_PORT",
        "/boaz/infra/EC2_B_ID", "/boaz/infra/RDS_IDENTIFIER", "/boaz/infra/S3_BUCKET", "/boaz/infra/TARGET_GROUP_ARN",
        "/boaz/infra/EXTRA",
      ]
      types = [for i in range(13) : "String"]
    }
  }

  expect_failures = [output.params_infra_count]
}

run "params_secure_string_is_rejected" {
  command = plan

  variables {
    season_capacity = "off"
    api_origin      = "ec2"
  }

  override_data {
    target = module.params.data.aws_ssm_parameters_by_path.infra
    values = {
      names = [
        "/boaz/infra/ALB_PORT", "/boaz/infra/ALB_SG_ID", "/boaz/infra/ALB_SUBNETS", "/boaz/infra/CLOUDFRONT_DIST_ID",
        "/boaz/infra/CODEDEPLOY_APP", "/boaz/infra/CODEDEPLOY_GROUP", "/boaz/infra/EC2_A_DOMAIN", "/boaz/infra/EC2_A_PORT",
        "/boaz/infra/EC2_B_ID", "/boaz/infra/RDS_IDENTIFIER", "/boaz/infra/S3_BUCKET", "/boaz/infra/TARGET_GROUP_ARN",
      ]
      types = concat(["SecureString"], [for i in range(11) : "String"])
    }
  }

  expect_failures = [output.params_infra_count]
}

# network: 다른 그룹이 쓰는 output의 키 구성 검사(NET-01-07, 공통 절차 1-1-2절 output 계약)
run "network_outputs_match_contract" {
  command = plan

  variables {
    season_capacity = "off"
    api_origin      = "ec2"
  }

  assert {
    condition     = keys(module.network.security_group_ids) == ["alb", "alb_to_ec2", "cf_to_ec2", "ec2_to_rds", "rds", "ssh"]
    error_message = "security_group_ids의 키는 alb, alb_to_ec2, cf_to_ec2, ec2_to_rds, rds, ssh여야 합니다."
  }
  assert {
    condition     = keys(module.network.public_subnet_ids) == ["a", "c"] && keys(module.network.private_subnet_ids) == ["a", "c"]
    error_message = "public_subnet_ids·private_subnet_ids의 키는 a, c여야 합니다."
  }
}
