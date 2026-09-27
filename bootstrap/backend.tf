# bootstrap state는 자기가 만든 state 버킷에 저장함. bucket 값만 gitignore된 backend.hcl로 넘김 (예시: backend.hcl.example)
#
# 최초 1회: 버킷이 아직 없으므로 local backend로 apply한 뒤 버킷으로 옮김
#   1. local_override.tf(gitignore 대상 *_override.tf)에 terraform { backend "local" {} } 작성
#   2. terraform init && terraform plan -out=bootstrap.tfplan && terraform apply bootstrap.tfplan
#   3. backend.hcl의 bucket이 terraform.tfvars의 state_bucket_name과 같은지 확인하고, 다르면 중단
#      (다르면 state가 Terraform이 관리하는 버킷이 아닌 다른 버킷으로 옮겨짐)
#   4. local_override.tf 삭제 후 terraform init -migrate-state -backend-config=backend.hcl
#   5. terraform state list로 자원 8개, terraform plan으로 "No changes" 확인
#   6. 로컬 terraform.tfstate* 삭제

terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
