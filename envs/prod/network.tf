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
}
