# state 전용 S3 버킷 (STA-03, docs/records/decisions.md "state 버킷·키")
# 버킷과 보호 설정 전부에 prevent_destroy를 걸어 삭제·교체 plan을 오류로 막음 (STA-03-02)
# 잠금은 S3 자체 잠금(use_lockfile)을 쓰므로 DynamoDB 테이블을 만들지 않음 (STA-03-03)

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # 같은 버킷 설정을 동시에 바꾸면 OperationAborted(409)가 날 수 있어 순서대로 적용
  depends_on = [aws_s3_bucket_ownership_controls.state]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# SSE-S3(AES256): KMS 고객 관리형 키는 키 삭제 시 state 복구 불가 위험과 관리 비용이 있어 쓰지 않음
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# HTTPS가 아닌 요청 거부. 특정 principal만 허용하는 정책은 apply 역할이 생기는 STA-11에서 추가
# (STA-05의 plan 역할은 역할 정책으로 state 조회·잠금 파일 쓰기만 받음. 지금 버킷 정책으로 principal을 좁히면 로컬 실행 세션이 막힐 수 있음)
data "aws_iam_policy_document" "state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  # 퍼블릭 액세스 차단이 먼저 적용된 뒤 정책을 붙임
  depends_on = [aws_s3_bucket_public_access_block.state]

  lifecycle {
    prevent_destroy = true
  }
}

# 이전 state 버전과 잠금 파일(.tflock) 삭제 마커가 계속 쌓이지 않도록 정리
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 20
    }
  }

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  # 버전 관리가 켜진 뒤에만 noncurrent 규칙이 의미가 있음
  depends_on = [aws_s3_bucket_versioning.state]

  lifecycle {
    prevent_destroy = true
  }
}
