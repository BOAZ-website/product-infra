# iam 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함(docs/guides/import-procedure.md 1-1-2절)

output "ec2_instance_profile_name" {
  description = "EC2 인스턴스 프로파일 이름(compute 그룹 EC2-A·B)"
  value       = aws_iam_instance_profile.ec2.name
}

output "codedeploy_service_role_arn" {
  description = "CodeDeploy 서비스 롤 ARN(deploy 그룹 deployment group)"
  value       = aws_iam_role.this["codedeploy"].arn
}
