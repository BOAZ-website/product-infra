# storage 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 이름·타입은 docs/guides/import-procedure.md 1-1-2절 output 계약 표를 따름
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함

output "bucket_regional_domain_names" {
  description = "프론트 버킷 리전 도메인 이름. 역할 키(www, admin) → 도메인(cdn S3 origin, CDN-02)"
  value       = { for k in ["www", "admin"] : k => aws_s3_bucket.this[k].bucket_regional_domain_name }
}

output "bundle_bucket_name" {
  description = "배포 번들 버킷 이름(deploy, DEP-02-03에서 연결)"
  value       = aws_s3_bucket.this["bundle"].bucket
}
