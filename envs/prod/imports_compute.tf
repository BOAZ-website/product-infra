# compute 그룹 import 블록 전용 파일 (담당 명세서: CMP, docs/wbs/24-cmp.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md
# - EC2-B 전원 상태(aws_ec2_instance_state)는 인스턴스 ID로 import함. import 직후 plan이 no-op인지 꼭 확인함(다르면 apply 때 EC2-B가 켜지거나 꺼짐)

import {
  for_each = local.group_vars.compute.instance_ids
  to       = module.compute.aws_instance.this[each.key]
  id       = each.value
}

import {
  to = module.compute.aws_ec2_instance_state.ec2_b
  id = local.group_vars.compute.instance_ids.ec2_b
}

import {
  to = module.compute.aws_eip.main
  id = local.group_vars.compute.eip_allocation_id
}

import {
  to = module.compute.aws_eip_association.main
  id = local.group_vars.compute.eip_association_id
}
