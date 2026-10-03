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

    # OBS Discord 알림 Lambda 코드(저장소 소스)를 zip으로 만들 때 사용(docs/wbs/20-obs.md OBS-01-06). 쓰기 전까지 미사용 경고를 무시함
    # tflint-ignore: terraform_unused_required_providers
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0.0, < 3.0.0"
    }
  }
}
