# VPC·서브넷·인터넷 게이트웨이
# - 설정값은 2026-10-26 재조사(docs/records/inventory.md 2절)와 같게 둠. 다르면 plan에 변경·교체가 나옴

resource "aws_vpc" "main" {
  cidr_block           = var.vpc.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc.name
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 퍼블릭 서브넷: 인스턴스에 퍼블릭 IP 자동 할당(EC2-A·B가 위치함)
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = each.value.name
  }
}

# 프라이빗 서브넷: 외부 경로 없음(NAT 없음). RDS 서브넷 그룹이 사용
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = each.value.name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.internet_gateway_name
  }
}
