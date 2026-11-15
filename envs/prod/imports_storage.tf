# storage 그룹 import 블록 전용 파일 (담당 명세서: STO, docs/wbs/23-sto.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md
# - 이름 기반 import. 버킷과 하위 리소스 모두 import id는 버킷 이름(storage.tf의 local.storage_buckets)

import {
  for_each = local.storage_buckets
  to       = module.storage.aws_s3_bucket.this[each.key]
  id       = each.value.name
}

import {
  for_each = local.storage_buckets
  to       = module.storage.aws_s3_bucket_server_side_encryption_configuration.this[each.key]
  id       = each.value.name
}

import {
  for_each = local.storage_buckets
  to       = module.storage.aws_s3_bucket_public_access_block.this[each.key]
  id       = each.value.name
}

import {
  for_each = { for k in local.storage_policy_keys : k => local.storage_buckets[k].name }
  to       = module.storage.aws_s3_bucket_policy.this[each.key]
  id       = each.value
}

import {
  to = module.storage.aws_s3_bucket_lifecycle_configuration.recruitment
  id = local.storage_buckets.recruitment.name
}
