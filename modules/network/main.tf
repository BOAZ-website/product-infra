# network 모듈
# 담당 명세서: NET (docs/wbs/21-net.md) · 이슈: #49 NET-01
# 관리 자원: VPC, 서브넷 4개, 라우트 테이블·연결, 인터넷 게이트웨이, 보안 그룹·규칙(규칙별 리소스), 기본 Network ACL(`aws_default_network_acl`), CloudFront prefix list 조회(data)
#
# 자원은 역할별 파일에 있음. 이 파일에는 자원을 두지 않음
# - vpc.tf: VPC, 서브넷, 인터넷 게이트웨이
# - routing.tf: 라우트 테이블, 라우트, 서브넷 연결, 기본 Network ACL
# - security_groups.tf: 보안 그룹, 규칙, CloudFront prefix list 조회
# - 작성 규칙: docs/guides/import-procedure.md 1-0-1절 "모듈 작성 규칙"
