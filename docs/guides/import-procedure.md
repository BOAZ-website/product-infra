# 그룹 import 공통 절차

기준일 2026-09-26 · Phase 2 1차·2차의 모든 import 티켓(NET-01, IAM-02, IAM-03, STO-01, CMP-01, CMP-02, RDB-01, CDN-02, DEP-02)에 적용

> 각 명세서에는 그 그룹에만 해당하는 항목만 적음. 이 페이지의 절차는 모든 그룹이 똑같이 따름
> 시작 조건: STA-07(안전 게이트) 완료. 이전에는 어떤 그룹도 import를 시작하지 않음

---

## 1. 파일 규칙

그룹마다 자기 파일만 수정함. 다른 그룹 파일을 고쳐야 하면 그 그룹 담당자에게 요청함

| 그룹 | 모듈 폴더 | envs/prod 파일 | import 블록 파일 | 명세서 |
| --- | --- | --- | --- | --- |
| network | `modules/network/` | `envs/prod/network.tf` | `envs/prod/imports/network.tf` | NET |
| iam | `modules/iam/` | `envs/prod/iam.tf` | `envs/prod/imports/iam.tf` | IAM |
| params | `modules/params/` | `envs/prod/params.tf` | `envs/prod/imports/params.tf` | IAM |
| storage | `modules/storage/` | `envs/prod/storage.tf` | `envs/prod/imports/storage.tf` | STO |
| compute | `modules/compute/` | `envs/prod/compute.tf` | `envs/prod/imports/compute.tf` | CMP |
| database | `modules/database/` | `envs/prod/database.tf` | `envs/prod/imports/database.tf` | RDB |
| cdn | `modules/cdn/` | `envs/prod/cdn.tf` | `envs/prod/imports/cdn.tf` | CDN |
| deploy | `modules/deploy/` | `envs/prod/deploy.tf` | `envs/prod/imports/deploy.tf` | DEP |

- 공통 파일(`envs/prod/versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `outputs.tf`)은 STA 담당만 수정함
- 그룹 간 값 전달(예: network의 서브넷 ID를 database가 사용)은 상대 그룹 모듈의 output을 참조함. 필요한 output이 없으면 해당 그룹 담당자에게 추가를 요청함
- import가 끝나 state에 등록된 뒤에는 `envs/prod/imports/<그룹>.tf`의 import 블록을 지워도 됨. 지우는 것은 plan "No changes" 확인 후 별도 커밋으로 함

## 2. apply 순서 규칙

state 파일은 하나라서 한 번에 한 사람만 apply할 수 있음

- `import-log.md`의 그룹 상태를 `대기` → `진행 중` → `완료`로 적음
- apply는 `진행 중`으로 먼저 적은 사람이 함. 동시에 `진행 중`인 그룹은 최대 1개
- 기다리는 사람은 `terraform plan`만 실행하며 코드를 맞춤. plan도 state 잠금을 잡으므로 동시에 실행하면 한쪽이 잠금을 못 얻어 실패할 수 있음. `terraform plan -lock-timeout=5m`처럼 잠금 대기 시간을 주고, 잠금을 끄는 옵션(`-lock=false`)은 쓰지 않음
- 잠금이 오래 풀리지 않으면 강제 해제(`force-unlock`)하지 말고 잠금을 잡은 사람에게 먼저 확인함

## 3. 작업 순서

| 단계 | 할 일 | 완료 확인 방법 |
| --- | --- | --- |
| 1. 착수 선언 | `import-log.md`에 그룹 상태 `진행 중`, 담당자, 시작 시각 기록. 브랜치 `feat/import-<그룹>` 생성 | import-log.md 해당 행 갱신 |
| 2. 직전 재조사 | 그 그룹 자원만 AWS CLI 읽기 명령으로 다시 조사해 inventory.md 갱신. 시크릿 값은 조회하지 않음 | inventory 갱신 시각이 착수 이후 |
| 3. 코드 작성 | import 블록을 먼저 쓰고 `terraform plan -generate-config-out=generated.tf`로 코드 초안 생성. 초안을 정리해 모듈·그룹 파일로 옮김 | `terraform validate` 통과 |
| 4. 보호 설정 | 보호 대상 자원에 `prevent_destroy` 추가. 재생성을 일으키는 속성은 실제 값과 똑같이 맞춤 | 코드에 `prevent_destroy` 존재 |
| 5. plan 맞추기 | `terraform plan`에서 차이가 0이 될 때까지 코드 수정. 교체·삭제가 나오면 즉시 멈추고 리뷰 요청 | plan 결과에 import만 있고 변경·교체·삭제 0건 |
| 6. PR | PR 템플릿 작성, plan 결과 첨부, 리뷰 1명 이상 승인 | PR에 승인 1건 이상 |
| 7. apply | 승인된 PR의 plan 파일로 apply(state 등록만 일어남) | apply 로그에 `import`만 존재 |
| 8. 최종 확인 | 같은 커밋에서 다시 `terraform plan` | 출력에 "No changes." 문구 |
| 9. 기록 | `import-log.md`에 대상 자원, plan 결과 문구, 남은 차이, 관리 제외 항목과 사유 기록. 그룹 상태 `완료` | import-log.md 해당 행 갱신 |

## 4. 멈춰야 하는 경우

- plan에 보호 자원(RDS, EC2, EIP, CloudFront, Route53, S3)의 교체(replace)나 삭제(delete)가 나온 경우
- 조사로 확정되지 않은 식별자를 써야 하는 경우(추정값 사용 금지)
- plan 출력에 비밀번호·시크릿 값이 보이는 경우
- 12월 시즌 동결 기간이거나 2027-01 앱 릴리스 월인 경우(→ OPS 명세서 참조)

멈춘 경우 PR에 상황을 적고 STA 담당과 해당 그룹 담당이 함께 확인함

## 5. 그룹 PR 리뷰 체크리스트

리뷰어는 아래 항목을 모두 확인한 뒤 승인함

- [ ] 수정 파일이 자기 그룹 파일(1절 표)뿐
- [ ] plan 결과에 변경·교체·삭제가 0건
- [ ] 보호 대상 자원에 `prevent_destroy`가 있음
- [ ] plan 출력과 코드에 시크릿 값, 계정 ID, 개인 IP가 없음
- [ ] 명세서의 그룹 고유 기능이 모두 반영됨
- [ ] `import-log.md`가 갱신됨
