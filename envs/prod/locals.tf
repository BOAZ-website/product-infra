# 공통 파일: STA 담당만 수정 (docs/guides/import-procedure.md 1절)
#
# 시즌 상태 모델 (SEA-01, docs/wbs/40-sea.md, design.md "시즌 상태 모델")
# - 그룹 모듈(compute·database·cdn)은 var.season_capacity·var.api_origin 대신 local.season만 넘겨받음
# - 대상 목록은 자원 ID가 아니라 역할 키(ec2_a, ec2_b, alb)로 적음. 실제 ID·DNS는 import한 자원 attribute로 연결
# - 시즌 시작·종료 순서 제어(재배포 게이트, 두 단계 apply)는 Phase 4(SEA-02·SEA-03) 범위
#
# | 항목                  | off(평시)  | on(모집 시즌)           |
# |-----------------------|------------|-------------------------|
# | ALB·listener          | 없음       | 있음(HTTP :80)          |
# | EC2-B                 | stopped    | running                 |
# | EC2-B 기능 태그       | 없음       | app = boaz-api          |
# | Target Group 대상     | EC2-A      | EC2-A, EC2-B            |
# | RDS Multi-AZ          | false      | true                    |
#
# | api_origin | origin 대상 | 포트 |
# |------------|-------------|------|
# | ec2        | EC2-A       | 8080 |
# | alb        | ALB         | 80   |

# 그룹 값 (docs/guides/import-procedure.md 1-1절)
# - 공개 저장소라 코드에 못 적는 값(data source로 못 찾는 import id, SSH 허용 CIDR 등)은 SSM String 파라미터 하나(JSON 객체)에 둠
# - 키는 <그룹>.<키>, 코드는 local.group_vars.<그룹>.<키>로 참조함. 값은 관리자만 갱신함
# - String 유형이라 KMS가 필요 없고 insecure_value가 sensitive로 표시되지 않음(SecureString이면 insecure_value가 null이라 postcondition으로 막음)
data "aws_ssm_parameter" "group_vars" {
  name = "/boaz/terraform/group-vars"

  lifecycle {
    postcondition {
      condition     = self.type == "String"
      error_message = "/boaz/terraform/group-vars는 String 유형이어야 합니다(SecureString이면 값을 읽지 않음)."
    }
  }
}

locals {
  season_capacity_model = {
    off = {
      alb_enabled           = false
      ec2_b_state           = "stopped"
      ec2_b_functional_tags = {}
      target_keys           = ["ec2_a"]
      rds_multi_az          = false
    }
    on = {
      alb_enabled           = true
      ec2_b_state           = "running"
      ec2_b_functional_tags = { app = "boaz-api" }
      target_keys           = ["ec2_a", "ec2_b"]
      rds_multi_az          = true
    }
  }

  api_origin_model = {
    ec2 = {
      target = "ec2_a"
      port   = 8080
    }
    alb = {
      target = "alb"
      port   = 80
    }
  }

  # 그룹 모듈에 넘기는 현재 시즌 상태. compute·database·cdn 그룹이 연결하기 전까지 미사용 경고를 무시함
  # tflint-ignore: terraform_unused_declarations
  season = merge(
    local.season_capacity_model[var.season_capacity],
    {
      capacity   = var.season_capacity
      api_origin = local.api_origin_model[var.api_origin]
    },
  )

  # 그룹 값 객체. 그룹이 참조하기 전까지 미사용 경고를 무시함
  # tflint-ignore: terraform_unused_declarations
  group_vars = jsondecode(data.aws_ssm_parameter.group_vars.insecure_value)
}
