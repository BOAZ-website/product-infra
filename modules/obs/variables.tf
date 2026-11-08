# obs 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/obs.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "name_prefix" {
  description = "새로 만드는 자원 이름 앞부분(예: SNS 주제, 경보 이름)"
  type        = string
}

# 경보 대상 조회용 이름. 자원 ID가 아니라 이름이라 코드에 적음(1-1절 2번 data source 조회)
# - compute·database 그룹이 import되면 output(ec2_a_id, db_instance_identifier) 참조로 바꿈(1-1-2절)
variable "ec2_a_name" {
  description = "EC2-A의 Name 태그 값. 상태 검사 경보 대상 조회용"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS 인스턴스 식별자(이름). RDS 경보 대상 조회용"
  type        = string
}

variable "app_log_group_name" {
  description = "앱 로그 그룹 이름. CloudWatch Agent 설정의 log_group_name과 같아야 함"
  type        = string
}

variable "log_retention_days" {
  description = "로그 그룹 보관 기간(일)"
  type        = number
}

variable "rds_freeable_memory_threshold_bytes" {
  description = "RDS 여유 메모리 경보 임계값(바이트). decisions.md \"경보 수신 이메일·임계값\""
  type        = number
}

# 모듈이 쓰는 키만 타입에 적음
variable "group_vars" {
  description = "obs 그룹 값(local.group_vars.obs)"
  type = object({
    alert_emails     = map(string) # 역할 키(ops_1 등) → 경보 수신 이메일
    distribution_ids = map(string) # 역할 키(api) → CloudFront 배포 ID. cdn 그룹 import 뒤 output 참조로 바꿈
  })

  validation {
    condition     = length(var.group_vars.alert_emails) > 0
    error_message = "group_vars.alert_emails에 수신 이메일이 1개 이상 있어야 합니다."
  }

  validation {
    condition     = contains(keys(var.group_vars.distribution_ids), "api")
    error_message = "group_vars.distribution_ids에 api 키가 있어야 합니다."
  }
}
