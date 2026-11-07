# 버킷 정책: www·admin(OAC 읽기), archiving(공개 읽기)
# - Version·Id·Sid·Statement 순서는 실제 정책 문서(s3api get-bucket-policy)와 같게 둠. 다르면 plan에 정책 변경이 생김
#
# CloudFront 배포 ARN(STO-01-05)
# - cdn 그룹이 storage output을 참조하므로 cdn output을 쓰면 순환 참조가 됨. data source로 조회함
# - data "aws_cloudfront_distribution"은 배포 ID로만 조회됨(별칭 조회 불가). ID는 그룹 값 storage.frontend_distribution_ids

data "aws_cloudfront_distribution" "frontend" {
  for_each = var.group_vars.frontend_distribution_ids

  id = each.value
}

locals {
  # TODO(재조사): 콘솔이 만드는 OAC 정책 기본 모양으로 적음. www·admin 실제 정책과 대조해 Version·Id·Sid를 맞추고, 둘이 다르면 키별로 나눔
  frontend_bucket_policies = {
    for k, distribution in data.aws_cloudfront_distribution.frontend : k => {
      Version = "2008-10-17"
      Id      = "PolicyForCloudFrontPrivateContent"
      Statement = [{
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this[k].arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = distribution.arn }
        }
      }]
    }
  }

  # 공개 읽기 정책 현행 유지(STO-01-03, decisions.md "공개 읽기 S3 버킷"). 공개 범위 변경은 별도 PR
  # TODO(재조사): 실제 정책과 대조해 Version·Sid를 맞춤
  archiving_bucket_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.this["archiving"].arn}/*"
    }]
  }

  bucket_policies = merge(local.frontend_bucket_policies, { archiving = local.archiving_bucket_policy })
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.bucket_policies

  bucket = aws_s3_bucket.this[each.key].id
  policy = jsonencode(each.value)

  lifecycle {
    prevent_destroy = true
  }
}
