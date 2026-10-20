# deploy 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/deploy.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "application_name" {
  description = "CodeDeploy 앱 이름(backend cd.yml이 참조, 바꾸지 않음)"
  type        = string
}

variable "deployment_group_name" {
  description = "CodeDeploy 배포 그룹 이름(backend cd.yml이 참조, 바꾸지 않음)"
  type        = string
}

variable "service_role_arn" {
  description = "배포 그룹 서비스 롤 ARN(module.iam.codedeploy_service_role_arn)"
  type        = string
}
