# 지원서 버킷 수명 주기: 30일 뒤 객체 만료(STO-01-02, decisions.md "지원서 버킷 수명 주기")
# - 코드에서 빠지면 수명 주기가 삭제되어 데이터 보존 동작이 바뀜. 삭제를 막기 위해 prevent_destroy를 둠
# - TODO(재조사): s3api get-bucket-lifecycle-configuration 결과와 대조함
#   - 필터: 응답이 `"Filter": {}`이면 아래 filter {} 그대로, `"Prefix": ""`(구식)이면 filter 대신 prefix = "" 로 바꿈
#   - 최소 객체 크기(transition_default_minimum_object_size): 응답 값이 all_storage_classes_128K가 아니면 그 값을 적음

resource "aws_s3_bucket_lifecycle_configuration" "recruitment" {
  bucket = aws_s3_bucket.this["recruitment"].id

  rule {
    id     = "expire-after-30days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
