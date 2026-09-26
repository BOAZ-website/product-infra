# RDB 데이터베이스 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

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
> 수정 파일: `modules/database/`, `envs/prod/database.tf`, `envs/prod/imports/database.tf`. 서브넷·보안 그룹 ID는 network 그룹 output을 참조

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | SEA-01, NET-01 | 없음 | Phase 2 2차 | 4.6, 6.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| RDB-01-01 | RDS 인스턴스·DB 서브넷 그룹·파라미터 그룹·보안 그룹을 조사로 확정한 식별자로 import | `terraform state list`에 4개 모두 존재 |
| RDB-01-02 | 삭제 방지 켜기, 삭제 시 최종 스냅샷 생성, 비밀번호는 변경 무시 목록에 넣음 | 코드에 세 설정 존재, plan에 비밀번호 차이 없음 |
| RDB-01-03 | 암호화 여부·암호화 키를 실제 값과 같게 맞춤(다르면 교체가 일어남). 키 ARN은 코드에 적지 않고 data source 참조나 저장소에 올리지 않는 변수 파일로 전달 | plan에 교체(replace) 없음 |
| RDB-01-04 | import 전 수동 스냅샷 생성 | `aws rds describe-db-snapshots`에 import 시점 스냅샷 존재 |
| RDB-01-05 | Multi-AZ는 `season_capacity` 변수와 연결하되 이번 import에서는 현재 값(꺼짐) 그대로 | plan에 Multi-AZ 변경 없음 |

---

## 확인 필요 사항

- 암호화 키 종류(AWS 관리 키인지 직접 만든 키인지) [확인 필요]
- 파라미터 그룹의 실제 파라미터 값 조사 [확인 필요]
- RDS 유지보수 시간(목요일 20:00 UTC)과 배포·DDL 일정이 겹치지 않는지 [확인 필요]
