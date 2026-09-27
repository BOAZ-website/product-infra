# 공통 파일: STA 담당만 수정 (docs/guides/import-procedure.md 1절)
#
# state는 bootstrap/이 만든 state 버킷의 envs/prod/terraform.tfstate에 저장함 (STA-04)
# 잠금은 S3 자체 잠금(use_lockfile)만 사용하고 DynamoDB 테이블은 쓰지 않음 (STA-04-01)
# bucket 값만 gitignore된 backend.hcl로 넘김 (예시: backend.hcl.example)
#
#   terraform init -input=false -backend-config=backend.hcl
#
# bootstrap 전(버킷이 없을 때)이나 backend.hcl이 없으면 init이 오류로 실패함 (STA-04-02)

terraform {
  backend "s3" {
    key          = "envs/prod/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
