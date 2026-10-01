# 공통 파일: STA 담당만 수정 (docs/guides/import-procedure.md 1절)
# 공개 저장소 규칙: 계정 ID는 코드에 적지 않고 gitignore된 terraform.tfvars로 넘김 (예시: terraform.tfvars.example)

variable "expected_account_id" {
  description = "plan·apply를 허용할 AWS 계정 ID. 다른 계정 자격 증명이면 plan 단계에서 실패함"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "AWS 계정 ID는 12자리 숫자여야 합니다."
  }
}

# 시즌 상태 변수 (SEA-01, docs/wbs/40-sea.md). 값은 커밋되는 season.auto.tfvars에서 관리함(시즌 전환도 PR로 남김)
# 기본값을 두지 않음: 기본값이 실제 상태와 다르면 plan에 ALB 삭제·EC2-B 중지·Multi-AZ 해제 같은 변경이 생기기 때문
# 그룹 모듈에는 이 변수 대신 locals.tf의 local.season을 넘김
variable "season_capacity" {
  description = "시즌 용량 상태. off: 평시(ALB 없음, EC2-B 중지, RDS 단일 AZ) / on: 모집 시즌(ALB 생성, EC2-B 기동, RDS Multi-AZ)"
  type        = string
  nullable    = false
  validation {
    condition     = contains(["off", "on"], var.season_capacity)
    error_message = "season_capacity는 off 또는 on만 허용합니다."
  }
}

variable "api_origin" {
  description = "api CloudFront 배포의 origin 대상. ec2: EC2-A:8080 / alb: ALB:80. alb는 season_capacity = on일 때만 허용"
  type        = string
  nullable    = false
  validation {
    condition     = contains(["ec2", "alb"], var.api_origin)
    error_message = "api_origin은 ec2 또는 alb만 허용합니다."
  }
  # ALB가 없는 상태(season_capacity = off)에서 origin을 ALB로 바꾸는 조합을 plan 전에 막음
  validation {
    condition     = !(var.api_origin == "alb" && var.season_capacity == "off")
    error_message = "api_origin = alb는 season_capacity = on일 때만 허용합니다. 시즌 시작은 season_capacity = on을 먼저 apply한 뒤 api_origin = alb로 바꿉니다."
  }
}
