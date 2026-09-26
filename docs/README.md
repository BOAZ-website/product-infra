# product-infra 문서 안내

운영 AWS 인프라를 Terraform으로 옮기는 작업의 문서 모음. 같은 내용을 노션에도 올림

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
| `overview/` | 배경·목표·원칙·시즌 전환 모델(`migration-plan.md`), 현행 인프라(`current-infra.md`) | 저장소 |
| `wbs/` | WBS와 명세서 12개. 티켓 키 `NET-01`, 기능 ID `NET-01-01` | 노션(이 폴더는 노션 페이지 원본 마크다운) |
| `guides/` | 팀원 공통 작업 절차 | 저장소 |
| `records/` | 조사 기록(inventory), 결정·확인 필요 레지스터(decisions), import 기록(import-log) | 저장소 |

`wbs/` 파일 번호: 0x 모두가 먼저 읽는 페이지 · 1x 사전 준비 · 2x Phase 2 1차 그룹 · 3x Phase 2 2차 그룹 · 4x 2027년 이후

## 문서 규칙

- 작업 순서·티켓·완료 조건의 기준은 노션 WBS·명세서. 노션을 고치면 같은 주 안에 `docs/wbs/`에 PR로 반영함
- `guides/`·`records/`는 저장소가 원본. 노션에는 링크로 둠
- `.kiro/specs/product-infra-migration/`(requirements·design·tasks)은 초기 설계 참고용. 명세서의 P1~P10 검증 속성 정의가 `design.md`에 있음. 내용이 WBS와 다르면 WBS를 따름
- 공인 IP·시크릿·키는 어떤 문서에도 적지 않음. 계정 ID·자원 ID는 `records/`에만 적고, 다른 문서에는 역할명으로 씀. 전체 규칙은 저장소 README의 "보안 정보 공개 금지"와 `CLAUDE.md`. `scripts/check-sensitive.sh`가 CI·커밋 전 훅에서 자동 검사함
- 문체는 개조식 명사형 종결(`~함`, `~됨`, `~있음`). 인칭 표현(우리 등)은 쓰지 않음
- 추정값은 `[추정]`, 확인되지 않은 사실은 `[확인 필요]`로 표기함. 일정이 정해지지 않은 기한은 티켓·Phase 기준(예: "STO-01 전", "Phase 2 2차 중")으로 적고, 일정 확정 후 날짜로 바꿈

