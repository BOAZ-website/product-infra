# deploy 모듈
# 담당 명세서: DEP (docs/wbs/27-dep.md) · 이슈: #63 DEP-01, #64 DEP-02
# 관리 자원: CodeDeploy 앱, 배포 그룹(`ec2_tag_set` app=boaz-api, AllAtOnce, 자동 롤백)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
