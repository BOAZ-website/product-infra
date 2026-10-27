# network 그룹: 네트워크(VPC·서브넷·라우팅·보안 그룹)
# 담당 명세서: NET (docs/wbs/21-net.md)
#
# - 이 파일은 network 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "network" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/network/에 작성
# - import 블록은 imports_network.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md

# 이름·사설 CIDR은 공개 가능한 값이라 직접 적음. 자원 ID는 그룹 값(local.group_vars.network)으로만 받음
module "network" {
  source = "../../modules/network"

  vpc = {
    name       = "boaz-prod-vpc"
    cidr_block = "10.0.0.0/16"
  }

  internet_gateway_name = "boaz-igw"

  public_subnets = {
    a = { name = "boaz-public-a", cidr_block = "10.0.1.0/24", availability_zone = "ap-northeast-2a" }
    c = { name = "boaz-public-c", cidr_block = "10.0.2.0/24", availability_zone = "ap-northeast-2c" }
  }

  private_subnets = {
    a = { name = "boaz-private-a", cidr_block = "10.0.11.0/24", availability_zone = "ap-northeast-2a" }
    c = { name = "boaz-private-c", cidr_block = "10.0.12.0/24", availability_zone = "ap-northeast-2c" }
  }

  route_table_names = {
    public  = "boaz-rtb-public"
    private = "boaz-rtb-private"
  }

  # 이름·설명은 실제 값과 같게 둠(다르면 교체됨). name_tag: Name 태그가 있는 그룹
  security_groups = {
    alb        = { name = "boaz-alb-sg", description = "for prod alb", name_tag = false }
    alb_to_ec2 = { name = "prod-alb-to-ec2-sg", description = "for alb to ec2", name_tag = false }
    cf_to_ec2  = { name = "prod-cf-to-ec2-sg", description = "cloudfront to ec2", name_tag = true }
    rds        = { name = "prod-rds-sg", description = "sg for rds", name_tag = true }
    ec2_to_rds = { name = "prod-ec2-to-rds-sg", description = "ec2 to rds", name_tag = true }
    ssh        = { name = "prod-ssh-sg", description = "ec2 ssh", name_tag = true }
  }

  # SSH 허용 CIDR은 그룹 값(ssh_allowed_cidrs)으로 받음. 설명은 역할 표기라 직접 적음
  ssh_rule_descriptions = {
    ops_1 = "backend-pm-home"
  }

  group_vars = local.group_vars.network
}
