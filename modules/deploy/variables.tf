# deploy 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/deploy.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)
