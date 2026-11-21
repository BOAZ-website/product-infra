# compute 그룹: EC2·EIP·Target Group·ALB
# 담당 명세서: CMP (docs/wbs/24-cmp.md)
#
# - 이 파일은 compute 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "compute" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/compute/에 작성
# - import 블록은 imports_compute.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

module "compute" {
  source = "../../modules/compute"

  season = local.season

  # 이름·태그·AMI는 실제 값과 같게 둠(2026-11-17 재조사, docs/records/inventory.md 4절)
  # EC2-A의 기능 태그(app=boaz-api)는 고정. EC2-B 기능 태그는 시즌 상태로 모듈이 더함
  # AMI는 ignore_changes 대상이라 바뀌어도 plan에 나오지 않음. 조회용 이름만 적음
  instances = {
    ec2_a = {
      name       = "boaz-api-prod-A"
      subnet_key = "a"
      tags       = { Environment = "prod", app = "boaz-api" }
      ami        = { owner = "amazon", name = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-20260421" }
    }
    ec2_b = {
      name       = "boaz-api-prod-B"
      subnet_key = "c"
      tags       = { Environment = "prod" }
      ami        = { owner = "self", name = "boaz-api-prod-img" }
    }
  }

  instance_type = "t3.small"
  key_name      = "boaz_codedeploy"

  root_volume = {
    type       = "gp3"
    size       = 20
    iops       = 3000
    throughput = 125
  }

  # 다른 그룹 output 참조(import-procedure.md 1-1-2절). ID를 코드나 그룹 값에 다시 적지 않음
  subnet_ids = module.network.public_subnet_ids
  security_group_ids = {
    for k in ["ec2_to_rds", "ssh", "cf_to_ec2", "alb_to_ec2"] : k => module.network.security_group_ids[k]
  }
  instance_profile_name = module.iam.ec2_instance_profile_name

  # Target Group은 실제 값과 같게 둠(2026-11-17 재조사, docs/records/inventory.md 6절)
  vpc_id = module.network.vpc_id
  target_group = {
    name              = "boaz-api-tg"
    port              = 8080
    health_check_path = "/actuator/health"
    tags              = { Environment = "prod", app = "boaz-api" }
  }

  # 시즌 on일 때만 만드는 ALB(docs/overview/current-infra.md "ALB")
  alb_name              = "boaz-alb"
  alb_security_group_id = module.network.security_group_ids["alb"]
}
