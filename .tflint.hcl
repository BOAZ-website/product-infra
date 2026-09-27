# TFLint 설정: CI(.github/workflows/ci.yml)와 로컬이 같은 설정을 씀. 버전은 CI와 함께 올림

tflint {
  required_version = ">= 0.64.0"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# 모든 variable·output에 description 필수 (STA-02-04)
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
