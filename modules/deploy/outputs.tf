# deploy 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 제안 이름: 필요 시 추가
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함

# backend workflow 배포 계약 검사(STA-10)용. 번들 버킷 output은 STO-01 머지 뒤 별도 PR(DEP-02-03)

output "application_name" {
  description = "CodeDeploy 앱 이름"
  value       = aws_codedeploy_app.this.name
}

output "deployment_group_name" {
  description = "CodeDeploy 배포 그룹 이름"
  value       = aws_codedeploy_deployment_group.this.deployment_group_name
}
