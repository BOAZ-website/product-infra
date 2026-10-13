# iam 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/iam.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "account_id" {
  description = "정책 문서의 ARN을 조립할 AWS 계정 ID(root의 var.expected_account_id)"
  type        = string
}

variable "group_vars" {
  description = "iam 그룹 값(local.group_vars.iam)"
  type = object({
    # 프론트 배포 정책의 CloudFront 무효화 대상. 역할 키(www, dev, admin) → 배포 ID. dev는 이미 삭제된 배포(현행 정책 그대로 import)
    distribution_ids = map(string)
  })
}
