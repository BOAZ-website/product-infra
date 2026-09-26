# 공통 파일: STA 담당만 수정 (docs/guides/import-procedure.md 1절)
# Terraform 1.11 이상: S3 backend 자체 잠금(use_lockfile) 정식 지원 버전
# AWS provider 6.x: docs/records/decisions.md "AWS provider 버전"

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
