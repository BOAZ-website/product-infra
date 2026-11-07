# storage 모듈
# 담당 명세서: STO (docs/wbs/23-sto.md) · 이슈: #54 STO-01
# 관리 자원: 관리 대상 버킷 5개와 버킷별 하위 리소스(버전 관리·암호화·퍼블릭 차단·수명 주기·정책 중 실제 설정이 있는 것만)
#
# - aws_s3_bucket에는 인라인 인자(versioning, server_side_encryption_configuration, lifecycle_rule, policy, acl 등)를 쓰지 않음(STO-01-01)
# - 하위 리소스는 실제 설정이 있는 버킷에만 둠. 없는 설정을 쓰면 plan에 create가 생김
# - 현행 값 근거: docs/records/inventory.md 13절
#
# | 역할 키     | 암호화 | 퍼블릭 차단 | 정책          | 수명 주기   | 버전 관리 |
# |-------------|--------|-------------|---------------|-------------|-----------|
# | www         | AES256 | 전체 false  | OAC 읽기      | 없음        | 없음      |
# | admin       | AES256 | 전체 true   | OAC 읽기      | 없음        | 없음      |
# | recruitment | AES256 | 전체 true   | 없음          | 30일 만료   | 없음      |
# | bundle      | AES256 | 전체 true   | 없음          | 없음        | 없음      |
# | archiving   | AES256 | 전체 false  | 공개 읽기     | 없음        | 없음      |
#
# - 버전 관리: 5개 모두 켠 적 없음(None)이라 aws_s3_bucket_versioning을 두지 않음
# - 정책은 policies.tf, 수명 주기는 lifecycle.tf
# - 버킷과 하위 리소스 전부에 prevent_destroy를 둠(bootstrap state 버킷과 같은 방식, STA-03-02). 하위 리소스를 지우는 변경은 prevent_destroy를 먼저 푸는 별도 PR로 함

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = each.value.name

  lifecycle {
    prevent_destroy = true
  }
}

# 5개 모두 기본 암호화 SSE-S3(AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 현행 값 그대로. 프론트 버킷(www) 차단 적용은 별도 승인·별도 PR(STO-01-04)
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = each.value.block_public_access
  block_public_policy     = each.value.block_public_access
  ignore_public_acls      = each.value.block_public_access
  restrict_public_buckets = each.value.block_public_access

  lifecycle {
    prevent_destroy = true
  }
}
