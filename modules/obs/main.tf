# obs 모듈
# 담당 명세서: OBS (docs/wbs/20-obs.md) · 이슈: #48 OBS-01
# 관리 자원: SNS 주제·구독, CloudWatch 경보, 로그 그룹(30일), Discord 알림 Lambda·실행 역할. CloudFront 지표 경보와 그 SNS 주제는 us-east-1
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
