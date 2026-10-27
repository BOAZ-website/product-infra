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

variable "route_table_names" {
  description = "public·private 라우트 테이블 이름(Name 태그). main 라우트 테이블은 태그 없음"
  type = object({
    public  = string
    private = string
  })
}

variable "security_groups" {
  description = "보안 그룹. 역할 키(alb, alb_to_ec2, cf_to_ec2, rds, ec2_to_rds, ssh) → 이름·설명·Name 태그 여부"
  type = map(object({
    name        = string
    description = string
    name_tag    = bool
  }))
}

variable "ssh_rule_descriptions" {
  description = "SSH 인바운드 규칙 설명. 키는 group_vars.ssh_allowed_cidrs와 같음(ops_1 등)"
  type        = map(string)
}

# 모듈이 쓰는 키만 타입에 적음. 나머지 키(import id 등)는 변환 때 버려짐
variable "group_vars" {
  description = "network 그룹 값(local.group_vars.network)"
  type = object({
    ssh_allowed_cidrs = map(string) # 역할 키(ops_1) → CIDR
  })
}
