# database 그룹: RDS
# 담당 명세서: RDB (docs/wbs/25-rdb.md)
#
# - 이 파일은 database 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "database" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/database/에 작성
# - import 블록은 imports_database.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
