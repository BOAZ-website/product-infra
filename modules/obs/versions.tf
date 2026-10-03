# obs 모듈 provider 요구 사항. 버전 범위는 envs/prod/versions.tf와 같게 유지함
# - archive provider는 Discord Lambda 작업(OBS-01-06) 때 추가함. 미리 넣으면 tflint 미사용 경고

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0.0, < 7.0.0"
      configuration_aliases = [aws.us_east_1] # us-east-1 자원·조회용. 호출부에서 providers = { aws = aws, aws.us_east_1 = aws.us_east_1 } 전달
    }
  }
}
