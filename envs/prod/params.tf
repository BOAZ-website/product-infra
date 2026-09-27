# params 그룹: SSM 파라미터
# 담당 명세서: IAM (docs/wbs/22-iam.md)
#
# - 이 파일은 params 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "params" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/params/에 작성
# - import 블록은 imports_params.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
