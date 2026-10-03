# params 모듈
# 담당 명세서: IAM (docs/wbs/22-iam.md) · 이슈: #52 IAM-03
# 관리 자원: SSM 파라미터 `/boaz/infra/*` 12개(정확히 12개 검사). `/boaz/terraform/group-vars`는 관리하지 않음
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
