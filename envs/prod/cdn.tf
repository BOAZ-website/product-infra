# cdn 그룹: CloudFront·Route53·ACM
# 담당 명세서: CDN (docs/wbs/26-cdn.md)
#
# - 이 파일은 cdn 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "cdn" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/cdn/에 작성
# - import 블록은 imports_cdn.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
