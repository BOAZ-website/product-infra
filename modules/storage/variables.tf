# storage 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/storage.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "buckets" {
  description = "관리 대상 버킷 5개. 역할 키(www, admin, recruitment, bundle, archiving) → 버킷 이름·퍼블릭 차단 여부(현행 값)"
  type = map(object({
    name                = string
    block_public_access = bool # 퍼블릭 차단 4개 설정을 모두 켰으면 true, 모두 껐으면 false
  }))

  validation {
    condition     = toset(keys(var.buckets)) == toset(["www", "admin", "recruitment", "bundle", "archiving"])
    error_message = "buckets의 키는 www, admin, recruitment, bundle, archiving 5개여야 합니다(decisions.md \"관리 대상 버킷·레코드\")."
  }
}

# 모듈이 쓰는 키만 타입에 적음
variable "group_vars" {
  description = "storage 그룹 값(local.group_vars.storage)"
  type = object({
    frontend_distribution_ids = map(string) # 역할 키(www, admin) → CloudFront 배포 ID(STO-01-05)
  })

  validation {
    condition     = toset(keys(var.group_vars.frontend_distribution_ids)) == toset(["www", "admin"])
    error_message = "group_vars.frontend_distribution_ids의 키는 www, admin이어야 합니다."
  }
}
