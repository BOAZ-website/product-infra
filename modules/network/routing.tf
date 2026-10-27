# 라우트 테이블·라우트·서브넷 연결·기본 Network ACL
# - 설정값은 2026-10-26 재조사(docs/records/inventory.md 2절)와 같게 둠
# - 라우트 테이블 안에 route 블록을 쓰지 않음. 생략하면 Terraform이 기존 라우트를 건드리지 않음. 라우트는 aws_route로 따로 둠

# main 라우트 테이블: VPC 생성 때 함께 생긴 기본 테이블. local 라우트만 있고 연결된 서브넷·태그 없음
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.route_table_names.public
  }
}

# private: local 라우트만 있음(NAT 없음)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.route_table_names.private
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# 기본 Network ACL 현행 그대로 편입(decisions.md "Network ACL 관리 방식")
# - ingress·egress 블록을 생략하면 규칙이 삭제되므로 100번 전체 허용을 명시함. 32767번 기본 거부는 AWS가 관리함
# - subnet_ids를 생략하면 차이가 계속 남으므로 서브넷 4개를 모두 적음
resource "aws_default_network_acl" "main" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id
  subnet_ids             = concat(values(aws_subnet.public)[*].id, values(aws_subnet.private)[*].id)

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}
