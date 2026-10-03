# cdn 모듈
# 담당 명세서: CDN (docs/wbs/26-cdn.md) · 이슈: #60 CDN-01, #61 CDN-02, #62 CDN-03
# 관리 자원: CloudFront 배포 3개, OAC 2개, Route53 영역·레코드, ACM 인증서(us-east-1), WAF WebACL 조회(참조만)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
