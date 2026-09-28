# 공개 저장소 규칙: 버킷 이름·계정 ID는 코드에 적지 않고 gitignore된 terraform.tfvars로 넘김
# 예시: terraform.tfvars.example

variable "state_bucket_name" {
  description = "Terraform state 전용 S3 버킷 이름"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "S3 버킷 이름 규칙(소문자·숫자·점·하이픈, 3~63자)을 따라야 합니다."
  }
}

variable "expected_account_id" {
  description = "apply를 허용할 AWS 계정 ID. 다른 계정 자격 증명이면 plan 단계에서 실패함"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "AWS 계정 ID는 12자리 숫자여야 합니다."
  }
}
