# params 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/params.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "names" {
  description = "관리할 `/boaz/infra` 하위 SSM 파라미터의 짧은 이름(경로 접두어 제외). root(envs/prod/params.tf)의 local.params_infra_names"
  type        = set(string)
}
