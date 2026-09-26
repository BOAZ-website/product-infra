# network 그룹: 네트워크(VPC·서브넷·라우팅·보안 그룹)
# 담당 명세서: NET (docs/wbs/21-net.md)
#
# - 이 파일은 network 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "network" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/network/에 작성
# - import 블록은 imports_network.tf에 작성
# - 작업 절차: docs/guides/import-procedure.md
