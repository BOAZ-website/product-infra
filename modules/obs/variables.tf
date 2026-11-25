# obs 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/obs.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "name_prefix" {
  description = "새로 만드는 자원 이름 앞부분(예: SNS 주제, 경보 이름)"
  type        = string
}

variable "alert_topic_name" {
  description = "기존 서울 리전 경보 SNS 주제 이름(import). 표시 이름도 같음"
  type        = string
}

# 경보 대상 조회용 이름. 자원 ID가 아니라 이름이라 코드에 적음(1-1절 2번 data source 조회)
# - compute·database 그룹이 import되면 output(instance_ids, db_instance_identifier) 참조로 바꿈(1-1-2절)
variable "ec2_names" {
  description = "EC2 Name 태그 값. 역할 키(ec2_a, ec2_b) → 이름. 경보 대상 조회용"
  type        = map(string)
}

variable "db_instance_identifier" {
  description = "RDS 인스턴스 식별자(이름). RDS 경보 대상 조회용"
  type        = string
}

variable "app_log_group_name" {
  description = "앱 로그 그룹 이름. CloudWatch Agent 설정의 log_group_name과 같아야 함"
  type        = string
}

variable "discord_webhook_parameter_name" {
  description = "Discord 웹훅 URL을 담은 SSM SecureString 이름(수동 등록, Terraform 관리 밖). 값은 Lambda가 실행 시 읽음"
  type        = string
}

variable "lambda_log_retention_days" {
  description = "Lambda 로그 그룹 보관 기간(일)"
  type        = number
}

variable "log_retention_days" {
  description = "앱 로그 그룹 보관 기간(일)"
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days는 CloudWatch Logs가 허용하는 보관 일수여야 합니다."
  }
}

variable "rds_log_types" {
  description = "로그 그룹을 관리할 RDS 로그 종류. RDS 로그 내보내기 이름(error, slowquery 등)과 같음"
  type        = list(string)

  validation {
    condition     = alltrue([for t in var.rds_log_types : contains(["error", "slowquery", "general", "audit"], t)])
    error_message = "rds_log_types는 error, slowquery, general, audit 중에서만 고를 수 있습니다."
  }
}

variable "rds_log_retention_days" {
  description = "RDS 로그 그룹 보관 기간(일). 앱 로그와 따로 둠(OBS-01-07)"
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.rds_log_retention_days)
    error_message = "rds_log_retention_days는 CloudWatch Logs가 허용하는 보관 일수여야 합니다."
  }
}

variable "existing_alarms" {
  description = "import하는 기존 경보. 역할 키 → 경보 설정(현행 값). target은 ec2_names의 키 또는 rds"
  type = map(object({
    name                = string
    description         = optional(string)
    target              = string
    namespace           = string
    metric              = string
    statistic           = string
    period              = number
    evaluation_periods  = number
    datapoints_to_alarm = optional(number)
    operator            = string
    threshold           = number
    treat_missing_data  = optional(string, "missing")
    ok_actions          = optional(bool, false)
    extra_dimensions    = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for a in var.existing_alarms : contains(["ec2_a", "ec2_b", "rds"], a.target)])
    error_message = "existing_alarms의 target은 ec2_a, ec2_b, rds 중 하나여야 합니다."
  }
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
