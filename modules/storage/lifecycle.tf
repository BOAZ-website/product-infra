# 지원서 버킷 수명 주기: 30일 뒤 객체 만료(STO-01-02, decisions.md "지원서 버킷 수명 주기")
# - 코드에서 빠지면 수명 주기가 삭제되어 데이터 보존 동작이 바뀜. 삭제를 막기 위해 prevent_destroy를 둠
# - 실제 설정(get-bucket-lifecycle-configuration, 2026-11-15 대조): Filter {}(버킷 전체), 최소 객체 크기 all_storage_classes_128K(provider 기본값과 같아 적지 않음)
# - filter {}를 적으면 import 뒤 plan에 filter 추가가 나옴(provider 6.66.0이 빈 Filter를 state에 남기지 않음). 그래서 filter를 적지 않음

resource "aws_s3_bucket_lifecycle_configuration" "recruitment" {
  bucket = aws_s3_bucket.this["recruitment"].id

  rule {
    id     = "expire-after-30days"
    status = "Enabled"

    expiration {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
