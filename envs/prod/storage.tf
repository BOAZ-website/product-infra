# storage 그룹: S3 버킷
# 담당 명세서: STO (docs/wbs/23-sto.md)
#
# - 이 파일은 storage 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "storage" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/storage/에 작성
# - import 블록은 imports_storage.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
