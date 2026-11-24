# RDB 데이터베이스 명세서

기준일 2026-11-24 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- RDS 인스턴스를 데이터 손실 없이 import함
- 비밀번호는 코드·plan·로그 어디에도 남기지 않음
- import 전·시즌 전환 전·DDL 적용 전에 반드시 수동 스냅샷을 만듦

**범위:** RDS 인스턴스, DB 서브넷 그룹, 파라미터 그룹, RDS 보안 그룹
**범위 밖:** DB 클래스 변경(여유 메모리 경보 결과에 따라 별도 승인), Multi-AZ 전환 자동화(→ SEA 명세서)

---

## RDB-01 RDS 그룹 import

**목적:** database 모듈을 작성하고 RDS 관련 자원을 import해 plan "No changes"를 확인함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/database/`, `envs/prod/database.tf`, `envs/prod/imports_database.tf`. 서브넷·보안 그룹 ID는 network 그룹 output을 참조
> 그룹 값 키·테스트: 코드에 못 적는 값은 `docs/guides/import-procedure.md` 1-1-1절의 키 규칙·키 표를 따름. 새 키와 import 블록을 쓰는 PR에서 `envs/prod/tests/season.tftest.hcl`의 자기 그룹 가짜 값과 import 대상 `override_resource`를 같은 PR에서 추가함(1-2절)

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | SEA-01, NET-01 | 없음 | Phase 2 2차 | 4.6, 6.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| RDB-01-01 | RDS 인스턴스·DB 서브넷 그룹·파라미터 그룹·보안 그룹을 조사로 확정한 식별자로 import | `terraform state list`에 4개 모두 존재 |
| RDB-01-02 | 삭제 방지 켜기, 삭제 시 최종 스냅샷 생성, 비밀번호는 변경 무시 목록에 넣음 | 코드에 세 설정 존재, plan에 비밀번호 차이 없음 |
| RDB-01-03 | 암호화 여부·암호화 키를 실제 값과 같게 맞춤(다르면 교체가 일어남). 키 ARN은 코드에 적지 않고 data source 참조나 SSM 그룹 값(`local.group_vars.database.<키>`, import-procedure.md 1-1절)으로 받음 | plan에 교체(replace) 없음 |
| RDB-01-04 | import 전 수동 스냅샷 생성 | `aws rds describe-db-snapshots`에 import 시점 스냅샷 존재 |
| RDB-01-05 | Multi-AZ는 `season_capacity` 변수와 연결하되 이번 import에서는 현재 값(꺼짐) 그대로 | plan에 Multi-AZ 변경 없음 |
| RDB-01-06 | CloudWatch Logs 로그 내보내기 목록(`enabled_cloudwatch_logs_exports`)을 실제 값(`error`, `slowquery`)과 같게 적음. 목록이 빠지면 import 뒤 첫 apply에서 내보내기가 꺼짐. 로그를 받는 로그 그룹은 OBS에서 관리하며(OBS-01-07), 느린 쿼리 로그 그룹을 Terraform으로 먼저 만든 뒤 내보내기를 켬(순서가 반대면 RDS가 무기한 보관 그룹을 먼저 만듦) | import 뒤 plan에 로그 내보내기와 파라미터 그룹 변경 없음 |

---

## 확인 필요 사항

- 암호화 키: AWS 관리형 기본 RDS 키(`alias/aws/rds`)로 확인(2026-10-02 조사). 고객 생성 키 아님 → Terraform 키 관리 불필요, `storage_encrypted = true`와 현행 키로 맞춰 교체 방지
- 파라미터 그룹 `boaz-prod-mysql84`: 기본값과 다른 값은 `time_zone = Asia/Seoul`(immediate) 하나뿐으로 확인(2026-10-02 조사). 엔진 MySQL 8.4.11
- 느린 쿼리 로그: 2026-11-27 season-up 전에 RDB 담당에게 알리고 콘솔로 켬(import 연기 중이라 콘솔 변경, 당일 decisions.md 기록). 파라미터 그룹에 `slow_query_log = 1`, `long_query_time = 1`, `log_output = FILE`을 넣고(세 값 모두 재부팅 없이 반영), 로그 내보내기에 `slowquery`를 추가함. 내보내기를 추가하면 인스턴스가 수정 중 상태가 되므로 사용 가능 상태로 돌아온 것을 확인한 뒤 season-up을 시작함. RDB import 때 이 세 파라미터도 코드에 적어야 plan에 변경이 없음(RDB-01-06). 느린 쿼리 로그의 SQL에는 실제 값이 남아 지원자 개인정보가 들어갈 수 있음
- RDS 유지보수 시간: `thu:20:00-thu:20:30` UTC(한국시간 금 05:00~05:30), 백업 창 `19:00-19:30` UTC, AutoMinorVersionUpgrade 켜짐으로 확인(2026-10-02 조사). 이 창에 배포·DDL이 겹치지 않게 함(2027-01 출결 기능 배포 주 겹침 여부는 OPS-03에서 확인)
