# obs 그룹: 모니터링·경보(SNS, CloudWatch 경보, Discord 알림 Lambda)
# 담당 명세서: OBS (docs/wbs/20-obs.md)
#
# - 이 파일은 obs 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "obs" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/obs/에 작성
# - 기존 자원을 import하지 않고 새로 만드는 그룹이라 imports_obs.tf는 없음
# - 경보 수신 이메일은 코드에 적지 않고 SSM 그룹 값(local.group_vars.obs.<키>)으로 받음(docs/guides/import-procedure.md 1-1절)
# - Discord 웹훅 URL은 시크릿이라 그룹 값에 넣지 않음. 수동 등록한 SecureString을 Lambda가 실행 시 읽음(OBS-01-06)
# - 작업 절차: docs/guides/import-procedure.md
