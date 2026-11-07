# storage 그룹: S3 버킷
# 담당 명세서: STO (docs/wbs/23-sto.md)
#
# - 이 파일은 storage 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "storage" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/storage/에 작성
# - import 블록은 imports_storage.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

# 관리 대상 버킷 5개(decisions.md "관리 대상 버킷·레코드"). 그 밖의 버킷은 관리 제외(STO-02)
# - 버킷 이름은 공개 가능한 값이라 그룹 값 키 없이 적음. import id 조립에도 씀(imports_storage.tf)
# - block_public_access는 현행 값(inventory.md 13절). www를 true로 바꾸는 것은 별도 승인·별도 PR(STO-01-04)
locals {
  storage_buckets = {
    www         = { name = "boaz-prod-frontend", block_public_access = false }
    admin       = { name = "boaz-prod-frontend-admin", block_public_access = true }
    recruitment = { name = "boaz-recruitment", block_public_access = true }
    bundle      = { name = "boaz-codedeploy-bucket", block_public_access = true }
    archiving   = { name = "boaz-archiving", block_public_access = false }
  }

  # 정책이 있는 버킷 키(modules/storage/policies.tf의 aws_s3_bucket_policy 키와 같음)
  storage_policy_keys = ["www", "admin", "archiving"]
}

module "storage" {
  source = "../../modules/storage"

  buckets    = local.storage_buckets
  group_vars = local.group_vars.storage
}
