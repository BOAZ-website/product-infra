# iam 모듈
# 담당 명세서: IAM (docs/wbs/22-iam.md) · 이슈: #51 IAM-02
# 관리 자원: GitHub OIDC provider, 롤 4개, 관리형 정책 연결·인라인 정책, EC2 인스턴스 프로파일(CI plan 역할은 bootstrap 관리라 제외)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
