# network 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/network.tf)에서 넘김
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)

variable "vpc" {
  description = "VPC 이름(Name 태그)·CIDR"
  type = object({
    name       = string
    cidr_block = string
  })
}

variable "internet_gateway_name" {
  description = "인터넷 게이트웨이 이름(Name 태그)"
  type        = string
}

variable "public_subnets" {
  description = "퍼블릭 서브넷. 가용 영역 키(a, c) → 이름·CIDR·가용 영역"
  type = map(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
}

variable "private_subnets" {
  description = "프라이빗 서브넷. 가용 영역 키(a, c) → 이름·CIDR·가용 영역"
  type = map(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
}
