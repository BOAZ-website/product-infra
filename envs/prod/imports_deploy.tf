# deploy 그룹 import 블록 전용 파일 (담당 명세서: DEP, docs/wbs/27-dep.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md
# - 이름 기반 import. 배포 그룹 id는 `<앱>:<배포 그룹>`

import {
  to = module.deploy.aws_codedeploy_app.this
  id = local.deploy_names.application
}

import {
  to = module.deploy.aws_codedeploy_deployment_group.this
  id = "${local.deploy_names.application}:${local.deploy_names.deployment_group}"
}
