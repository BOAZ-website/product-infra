# database 모듈
# 담당 명세서: RDB (docs/wbs/25-rdb.md) · 이슈: #59 RDB-01
# 관리 자원: RDS 인스턴스, DB 서브넷 그룹, 파라미터 그룹(RDS 보안 그룹은 network가 관리)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
