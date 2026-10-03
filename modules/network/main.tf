# network 모듈
# 담당 명세서: NET (docs/wbs/21-net.md) · 이슈: #49 NET-01
# 관리 자원: VPC, 서브넷 4개, 라우트 테이블·연결, 인터넷 게이트웨이, 보안 그룹·규칙(규칙별 리소스), 기본 Network ACL(`aws_default_network_acl`), CloudFront prefix list 조회(data)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
