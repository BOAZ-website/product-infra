# network 그룹 import 블록 전용 파일 (담당 명세서: NET, docs/wbs/21-net.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md
# - 규칙·연결 import id는 그룹 값의 ID를 조합해 만듦(라우트: `<라우트 테이블 ID>_<CIDR>`, 서브넷 연결: `<서브넷 ID>/<라우트 테이블 ID>`)

import {
  to = module.network.aws_vpc.main
  id = local.group_vars.network.vpc_id
}

import {
  for_each = local.group_vars.network.public_subnet_ids
  to       = module.network.aws_subnet.public[each.key]
  id       = each.value
}

import {
  for_each = local.group_vars.network.private_subnet_ids
  to       = module.network.aws_subnet.private[each.key]
  id       = each.value
}

import {
  to = module.network.aws_internet_gateway.main
  id = local.group_vars.network.internet_gateway_id
}

# main 라우트 테이블은 VPC ID로 import함
import {
  to = module.network.aws_default_route_table.main
  id = local.group_vars.network.vpc_id
}

import {
  to = module.network.aws_route_table.public
  id = local.group_vars.network.route_table_ids.public
}

import {
  to = module.network.aws_route_table.private
  id = local.group_vars.network.route_table_ids.private
}

import {
  to = module.network.aws_route.public_internet
  id = "${local.group_vars.network.route_table_ids.public}_0.0.0.0/0"
}

import {
  for_each = local.group_vars.network.public_subnet_ids
  to       = module.network.aws_route_table_association.public[each.key]
  id       = "${each.value}/${local.group_vars.network.route_table_ids.public}"
}

import {
  for_each = local.group_vars.network.private_subnet_ids
  to       = module.network.aws_route_table_association.private[each.key]
  id       = "${each.value}/${local.group_vars.network.route_table_ids.private}"
}

import {
  to = module.network.aws_default_network_acl.main
  id = local.group_vars.network.default_network_acl_id
}

import {
  for_each = local.group_vars.network.security_group_ids
  to       = module.network.aws_security_group.main[each.key]
  id       = each.value
}

# 규칙 import id는 규칙 ID(sgr-...)
import {
  for_each = local.group_vars.network.ingress_rule_ids
  to       = module.network.aws_vpc_security_group_ingress_rule.main[each.key]
  id       = each.value
}

import {
  for_each = local.group_vars.network.egress_rule_ids
  to       = module.network.aws_vpc_security_group_egress_rule.main[each.key]
  id       = each.value
}

import {
  for_each = local.group_vars.network.ssh_rule_ids
  to       = module.network.aws_vpc_security_group_ingress_rule.ssh[each.key]
  id       = each.value
}