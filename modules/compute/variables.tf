# compute 모듈 입력
# - 모든 variable에 type과 description 필수(tflint)
# - 자원 ID·IP·계정 ID·환경 이름을 default로 넣지 않음. 값은 root(envs/prod/compute.tf)에서 넘김
# - 시즌 입력은 `season` 하나(= local.season)로 받음
# - 그룹 값은 `group_vars`(= local.group_vars.<그룹>, 자기 그룹 부분만)로 받음
# - 쓰지 않는 variable은 선언하지 않음(tflint 미사용 경고)
# - CMP-01 범위의 import id는 root(imports_compute.tf)에서만 쓰므로 모듈은 아직 group_vars를 받지 않음

variable "season" {
  description = "시즌 상태(local.season). EC2-B 전원 상태와 기능 태그만 씀"
  type = object({
    ec2_b_state           = string
    ec2_b_functional_tags = map(string)
  })
}

variable "instances" {
  description = "인스턴스. 역할 키(ec2_a, ec2_b) → Name 태그·서브넷 키(a, c)·Name 외 태그·AMI(소유자 별칭·이름). EC2-B 기능 태그는 season에서 더함"
  type = map(object({
    name       = string
    subnet_key = string
    tags       = map(string)
    ami = object({
      owner = string # 소유자 별칭(amazon, self). 계정 ID를 쓰지 않음
      name  = string
    })
  }))

  validation {
    condition     = toset(keys(var.instances)) == toset(["ec2_a", "ec2_b"])
    error_message = "instances의 키는 ec2_a, ec2_b 두 개여야 합니다."
  }
}

variable "instance_type" {
  description = "EC2-A·EC2-B 공통 인스턴스 타입. 타입 변경은 이 모듈 범위 밖(DOC-12 수동 승인 절차)"
  type        = string
}

variable "key_name" {
  description = "EC2-A·EC2-B 공통 key pair 이름. 다르면 교체됨"
  type        = string
}

variable "root_volume" {
  description = "EC2-A·EC2-B 공통 루트 볼륨 설정(gp3). 암호화 여부는 모듈에서 실제 값(false)으로 고정"
  type = object({
    type       = string
    size       = number
    iops       = number
    throughput = number
  })
}

variable "subnet_ids" {
  description = "퍼블릭 서브넷 ID. 가용 영역 키(a, c) → ID(module.network.public_subnet_ids)"
  type        = map(string)
}

variable "security_group_ids" {
  description = "EC2-A·EC2-B 공통 보안 그룹 ID. 역할 키 → ID(module.network.security_group_ids에서 EC2용 4개)"
  type        = map(string)
}

variable "instance_profile_name" {
  description = "EC2 인스턴스 프로파일 이름(module.iam.ec2_instance_profile_name)"
  type        = string
}
