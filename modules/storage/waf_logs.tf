# WAF 로그 버킷(STO-01-06, 이슈 #120)
# - api 웹 ACL(us-east-1)의 WAF 로그를 서울 버킷에 쌓음. 웹 ACL은 Terraform 밖이라 로깅 설정은 콘솔로 함(20-obs.md "WAF 로그 설정")
# - WAF가 S3로 로그를 보내려면 버킷 이름이 aws-waf-logs-로 시작해야 함
# - 새로 만드는 버킷이라 관리 대상 버킷 5개(var.buckets)와 따로 둠. 기존 5개 코드는 바꾸지 않음
# - 로그에 요청 IP·경로가 남음. 비공개 버킷이고 열람은 관리자만 함. Authorization·Cookie 헤더는 웹 ACL 로깅 설정에서 가림
# - 다른 버킷과 같이 버킷과 하위 리소스 전부에 prevent_destroy를 둠

data "aws_caller_identity" "current" {}

locals {
  # 로그 전달 서비스가 쓰는 경로(AWSLogs/<계정>/WAFLogs/...)와 출처 조건
  waf_log_account_id = data.aws_caller_identity.current.account_id
  waf_log_source_arn = "arn:aws:logs:*:${local.waf_log_account_id}:*" # 웹 ACL은 us-east-1, 버킷은 서울이라 리전은 고정하지 않음
}

resource "aws_s3_bucket" "waf_logs" {
  bucket = var.waf_log_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  # ACL을 쓰지 않음. 로그 전달 서비스의 bucket-owner-full-control 업로드는 이 설정에서도 허용됨
  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    prevent_destroy = true
  }
}

# 다른 버킷과 같은 SSE-S3. KMS 키를 쓰면 로그 전달 서비스에 키 권한을 따로 줘야 함
resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 90일 뒤 삭제(개선안 4.F). filter는 지원서 버킷과 같은 이유로 적지 않음(lifecycle.tf 주석)
resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    id     = "expire-after-90days"
    status = "Enabled"

    expiration {
      days = var.waf_log_retention_days
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 로그 전달 서비스(delivery.logs.amazonaws.com)가 이 계정의 로그만 쓰도록 허용(AWS 문서의 S3 로그 전달 정책 모양)
# - 콘솔에서 로깅을 켤 때 정책이 이미 있으면 그대로 씀. 콘솔이 정책을 바꾸면 다음 storage plan에 차이가 나오므로 그때 코드에 맞춤
resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${local.waf_log_account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = local.waf_log_account_id }
          ArnLike      = { "aws:SourceArn" = local.waf_log_source_arn }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.waf_logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.waf_log_account_id }
          ArnLike      = { "aws:SourceArn" = local.waf_log_source_arn }
        }
      },
    ]
  })

  # 퍼블릭 차단을 먼저 걸어 둠
  depends_on = [aws_s3_bucket_public_access_block.waf_logs]

  lifecycle {
    prevent_destroy = true
  }
}
