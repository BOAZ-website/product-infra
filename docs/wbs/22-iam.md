# IAM 권한·파라미터 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- GitHub OIDC, 배포 롤, EC2 인스턴스 프로파일, `/boaz/infra/*` 파라미터 12개를 코드로 관리함
- 앱 시크릿은 존재와 타입만 확인하고 값은 조회·기록하지 않음
- 관리자 콘솔 배포 Role 권한 변경(#13 R2)은 IAM import 전에 끝냄. import 뒤에 콘솔로 바꾸면 곧바로 코드와 실제가 달라지기 때문

**범위:** IAM 롤·정책·OIDC provider·인스턴스 프로파일, SSM 인프라 파라미터, 앱 시크릿 존재 확인
**범위 밖:** 앱 시크릿 값 관리, `/boaz/app/*` 이관(후속 작업)

---

## IAM-01 배포 Role 권한 콘솔 적용 + 재조사

**목적:** 관리자 콘솔 프론트 배포에 필요한 권한을 먼저 콘솔·CLI로 적용하고 IAM 자원만 다시 조사함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-07 | 없음(재조사가 IAM-02 시작 조건) | Phase 2 1차 | 신규 | #13(R2) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| IAM-01-01 | 기존 프론트 배포 롤의 신뢰 정책에 관리자 콘솔 저장소 추가 | `aws iam get-role` 결과의 신뢰 정책에 저장소 조건 존재 |
| IAM-01-02 | 연결 정책에 관리자 콘솔 버킷·배포 권한 추가 | 정책 JSON에 해당 버킷 ARN 포함 |
| IAM-01-03 | 변경 전후 정책 차이를 decisions.md·Import_Log에 기록 | 문서에 변경 전후 비교 존재 |
| IAM-01-04 | 변경 직후 IAM 자원만 CLI로 다시 조사해 inventory 갱신 | inventory IAM 절 갱신 시점이 변경 이후 |

## IAM-02 IAM 롤·정책 그룹 import

**목적:** iam 모듈을 작성하고 롤·정책을 import해 plan "No changes"를 확인함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조. 직전 재조사는 IAM-01-04로 대신함
> 수정 파일: `modules/iam/`, `envs/prod/iam.tf`, `envs/prod/imports_iam.tf`

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | IAM-01 | 없음 | Phase 2 1차 | 4.2, 6.2(IAM 부분) | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| IAM-02-01 | GitHub OIDC provider, backend·frontend 배포 롤, CodeDeploy 서비스 롤, EC2 인스턴스 프로파일 import | `terraform state list`에 각 주소 존재 |
| IAM-02-02 | 롤에 붙은 정책 연결과 인라인 정책도 함께 import | plan에 정책 연결 삭제 없음 |
| IAM-02-03 | Terraform plan용 롤과 apply용 롤은 bootstrap에서 관리자 권한으로 먼저 만들고, 신뢰 조건을 운영 환경(`environment:production`)으로 제한 | 두 롤이 서로 다른 ARN, 코드에 액세스 키 없음 |
| IAM-02-04 | EC2 롤에 현재 연결된 권한을 그대로 import: 관리형 정책 5개(S3 읽기, Session Manager, CloudWatch Agent 전송 — OBS-01에 필요, 아카이빙·지원서 버킷 접근 2개)와 인라인 정책 3개(CodeDeploy 읽기, SSM 파라미터 읽기, CloudWatch 지표 조회). 권한 축소는 plan "No changes" 확인 뒤 별도 PR | plan에 정책 연결 변경 없음, 조사 기록(`docs/records/inventory.md`)의 관리형 5개·인라인 3개와 일치 |
| IAM-02-05 | EC2 인스턴스 프로파일은 iam 그룹이 관리하고 compute 그룹에 output으로 제공 | compute 코드가 iam output을 참조 |

## IAM-03 SSM 파라미터 그룹 import + P7

**목적:** params 모듈을 작성하고 `/boaz/infra/*` 12개를 import함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/params/`, `envs/prod/params.tf`, `envs/prod/imports_params.tf`

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | IAM-01 | 앱 시크릿 SecureString 범위 | Phase 2 1차 | 4.3, 6.2(SSM 부분), 8.4 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| IAM-03-01 | `/boaz/infra/*`는 정확히 12개. 개수가 다르면 plan 실패 | 13개로 바꾼 테스트에서 실패 |
| IAM-03-02 | 앱 시크릿은 존재·타입·암호화 키만 확인. 복호화 조회 안 함, output에 노출 안 함 | plan 출력에 시크릿 값 없음 |
| IAM-03-03 | P7 테스트: 파라미터 값은 직접 입력하지 않고 관리 자원의 속성에서 가져옴 | `pytest -k P7` 통과 |
| IAM-03-04 | 기존 `register-ssm-params.sh`를 실행 경로에서 참조하지 않음 | 검사 결과 참조 0건 |

## IAM-04 앱 시크릿 잔여 항목 결정·적용

**목적:** 아직 일반 문자열로 저장된 앱 시크릿 2개의 암호화 저장(SecureString) 전환 여부를 정함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | IAM-03 | 앱 시크릿 SecureString 범위 | Phase 2 1차 | 신규 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| IAM-04-01 | DB 접속 주소·DB 사용자명 파라미터의 전환 여부를 운영진 승인으로 확정 | decisions.md 상태 "결정 완료" |
| IAM-04-02 | 승인 시 전환 계획·되돌리기 절차 작성 후 적용 | 적용 후 파라미터 타입이 SecureString |

---

## 확인 필요 사항

- 전환하면 백엔드 `load-ssm-env.sh` 동작에 영향이 있는지 [확인 필요: 백엔드 리드]
- Terraform 실행 자격 증명이 장기 액세스 키인지 [확인 필요]
