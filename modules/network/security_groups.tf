# 보안 그룹·규칙
# - 설정값은 2026-10-26 재조사(docs/records/inventory.md 3절)와 같게 둠. 이름·설명이 다르면 보안 그룹이 교체됨
# - aws_security_group 안에 인라인 ingress·egress 블록을 쓰지 않음. 규칙은 규칙별 리소스로 둠(NET-01-03)
# - 규칙 for_each 키는 보안 그룹 역할 키와 같음(보안 그룹마다 인바운드·아웃바운드 규칙 1개씩. SSH 인바운드만 허용 IP마다 1개)

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  # 출발지는 prefix list(prefix_list_id) 또는 다른 보안 그룹 역할 키(source_sg) 중 하나
  ingress_rules = {
    alb        = { port = 80, prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id, source_sg = null }
    alb_to_ec2 = { port = 8080, prefix_list_id = null, source_sg = "alb" }
    cf_to_ec2  = { port = 8080, prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id, source_sg = null }
    rds        = { port = 3306, prefix_list_id = null, source_sg = "ec2_to_rds" }
  }

  # 기본 아웃바운드(전체 허용)도 명시함(NET-01-06). ec2_to_rds만 기본 규칙이 제거되고 RDS 보안 그룹 3306만 허용
  egress_rules = {
    alb        = { ip_protocol = "-1", port = null, cidr_ipv4 = "0.0.0.0/0", destination_sg = null }
    alb_to_ec2 = { ip_protocol = "-1", port = null, cidr_ipv4 = "0.0.0.0/0", destination_sg = null }
    cf_to_ec2  = { ip_protocol = "-1", port = null, cidr_ipv4 = "0.0.0.0/0", destination_sg = null }
    rds        = { ip_protocol = "-1", port = null, cidr_ipv4 = "0.0.0.0/0", destination_sg = null }
    ec2_to_rds = { ip_protocol = "tcp", port = 3306, cidr_ipv4 = null, destination_sg = "rds" }
    ssh        = { ip_protocol = "-1", port = null, cidr_ipv4 = "0.0.0.0/0", destination_sg = null }
  }
}

resource "aws_security_group" "main" {
  for_each = var.security_groups

  name        = each.value.name
  description = each.value.description
  vpc_id      = aws_vpc.main.id

  # alb·alb_to_ec2는 태그 없음, 나머지는 Name = 그룹 이름
  tags = each.value.name_tag ? { Name = each.value.name } : null
}

resource "aws_vpc_security_group_ingress_rule" "main" {
  for_each = local.ingress_rules

  security_group_id            = aws_security_group.main[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.source_sg == null ? null : aws_security_group.main[each.value.source_sg].id
}

resource "aws_vpc_security_group_egress_rule" "main" {
  for_each = local.egress_rules

  security_group_id            = aws_security_group.main[each.key].id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.destination_sg == null ? null : aws_security_group.main[each.value.destination_sg].id
}

# SSH 인바운드: 허용 IP 1개당 규칙 1개. CIDR은 그룹 값에서 받아 코드에 남지 않음. 규칙 내용은 바꾸지 않음(NET-01-05)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.group_vars.ssh_allowed_cidrs

  security_group_id = aws_security_group.main["ssh"].id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
  description       = var.ssh_rule_descriptions[each.key]
}
