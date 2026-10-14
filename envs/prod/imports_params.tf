# params 그룹 import 블록 전용 파일 (담당 명세서: IAM, docs/wbs/22-iam.md)
#
# - import 블록은 root 모듈(envs/prod) 바로 아래 파일에만 둘 수 있으므로 하위 폴더를 쓰지 않음
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙, README "보안 정보 공개 금지")
# - 작업 절차: docs/guides/import-procedure.md

# String인 파라미터만 import함. aws_ssm_parameter는 읽을 때 항상 복호화하므로, SecureString으로 바뀐 이름은 import 조회 자체를 하지 않음
# - 걸러진 이름은 envs/prod/params.tf의 타입 검사(output precondition)가 plan을 실패시킴
import {
  for_each = setintersection(local.params_infra_names, local.params_infra_string_names)
  to       = module.params.aws_ssm_parameter.infra[each.key]
  id       = "/boaz/infra/${each.key}"
}
