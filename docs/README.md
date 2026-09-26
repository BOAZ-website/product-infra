# product-infra 문서 안내

운영 AWS 인프라를 Terraform으로 옮기는 작업의 문서 모음. 같은 내용을 노션에도 올린다.

## 역할별 읽기 순서

**Phase 2부터 그룹을 맡은 팀원**

1. `wbs/00-wbs.md` — 읽는 법, 담당 구분, **import 그룹 배정표**(내 그룹·티켓·수정 파일 확인)
2. `guides/import-procedure.md` — 모든 그룹이 따르는 공통 절차(파일 규칙, apply 순서, 작업 9단계, PR 체크리스트)
3. 내 그룹 명세서(`wbs/2x-*.md` 또는 `wbs/3x-*.md`) — 그룹 고유 기능과 완료 확인 방법
4. 필요할 때: `overview/migration-plan.md`(배경·원칙), `records/inventory.md`(조사 기록)

**인프라 리드(Phase 0~1)**

1. `overview/migration-plan.md` → `wbs/00-wbs.md` → `wbs/1x-*.md`(사전 준비 명세서)

## 디렉터리

| 경로 | 내용 | 원본 |
| --- | --- | --- |
| `overview/` | 배경·목표·원칙·시즌 전환 모델, 현행 인프라 설명 | 저장소 |
| `wbs/` | WBS와 명세서 12개. 티켓 키 `NET-01`, 기능 ID `NET-01-01` | 노션(이 폴더는 노션 페이지 원본 마크다운) |
| `guides/` | 팀원 공통 작업 절차 | 저장소 |
| `records/` | 조사 기록(inventory), 결정 기록(decisions), import 기록(import-log) | 저장소 |

`wbs/` 파일 번호: 0x 모두가 먼저 읽는 페이지 · 1x 사전 준비 · 2x MS2a 그룹 · 3x MS2b 그룹 · 4x 2027년 이후

## 문서 규칙

- 작업 순서·티켓·완료 조건의 기준은 노션 WBS·명세서. 노션을 고치면 같은 주 안에 `docs/wbs/`에 PR로 반영한다.
- `guides/`·`records/`는 저장소가 원본. 노션에는 링크로 둔다.
- `.kiro/specs/product-infra-migration/`(requirements·design·tasks)은 초기 설계 참고용. 명세서의 P1~P10 검증 속성 정의가 `design.md`에 있다. 내용이 WBS와 다르면 WBS를 따른다.
- 계정 ID, 개인 IP는 어떤 문서에도 적지 않는다. 자원 식별자는 `records/inventory.md`에만 적는다.

## 정리 예정

- `infra-spec.md` → `overview/current-infra.md`로 이동, SSH 허용 개인 IP 삭제(PR #10 머지 후)
- PR #10의 `inventory.md`·`decisions.md`·`import-log.md` → `records/`로 이동(PR #10 머지 후)
- PR #12의 `wbs.md`는 `wbs/`로 대체되어 머지하지 않고 닫음
