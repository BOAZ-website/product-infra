# database 모듈 provider 요구 사항. 버전 범위는 envs/prod/versions.tf와 같게 유지함

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
