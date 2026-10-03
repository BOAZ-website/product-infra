# 시즌 변수·상태 모델 검사 (SEA-01). AWS에 요청하지 않음(mock provider, backend 미사용)
#   terraform -chdir=envs/prod init -backend=false
#   terraform -chdir=envs/prod test

mock_provider "aws" {
  # 그룹 값 파라미터(locals.tf)는 빈 JSON 객체로 대체함
  override_data {
    target = data.aws_ssm_parameter.group_vars
    values = {
      type           = "String"
      insecure_value = "{}"
    }
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
    condition     = local.group_vars == {}
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
