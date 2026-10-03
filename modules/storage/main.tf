# storage 모듈
# 담당 명세서: STO (docs/wbs/23-sto.md) · 이슈: #54 STO-01
# 관리 자원: 관리 대상 버킷 5개와 버킷별 하위 리소스(버전 관리·암호화·퍼블릭 차단·수명 주기·정책 중 실제 설정이 있는 것만)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
