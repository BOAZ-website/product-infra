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
