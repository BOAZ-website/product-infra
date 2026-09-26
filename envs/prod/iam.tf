# iam 그룹: IAM 롤·정책·OIDC·인스턴스 프로파일
# 담당 명세서: IAM (docs/wbs/22-iam.md)
#
# - 이 파일은 iam 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "iam" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/iam/에 작성
# - import 블록은 imports_iam.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
