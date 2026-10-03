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
| IAM-02-03 | CI용 plan 역할은 bootstrap에서 이미 관리함(신뢰 조건 `pull_request`). apply 역할은 STA-11(Phase 3) 범위임. 이 티켓에서는 두 역할을 만들거나 import하지 않음. 이유는 같은 자원의 이중 관리 방지임 | envs/prod 코드에 CI 역할 없음, 코드에 액세스 키 없음 |
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

> 앱 시크릿 확인 방법: `aws ssm describe-parameters`(이름·타입·KMS 키 등 메타데이터만, 값 없음)로 확인하고 결과는 `docs/records/`에 이름·타입만 기록함. 다음은 쓰지 않음
> - `aws_ssm_parameter` resource로 import: plan이 값을 복호화해 읽음. PR CI plan 역할은 `kms:Decrypt`를 거부해 plan이 실패하고, 값이 state에 들어가 안전 게이트 G2도 차단함(STA-05·STA-07)
> - `data "aws_ssm_parameter"`: 기본이 복호화 조회이고, `with_decryption = false`여도 암호문이 state에 남음
> - `aws ssm get-parameter --with-decryption`(CLAUDE.md "시크릿은 조회 자체를 하지 않는다")
| IAM-03-03 | P7 테스트: 파라미터 값은 직접 입력하지 않고 관리 자원의 속성에서 가져옴. 값의 출처에 2차 그룹(compute·database·cdn·deploy)이 포함됨. 이 티켓은 import와 개수 검사까지 함. P7 테스트는 Phase 2 2차 머지 뒤 별도 PR(STA-08)에서 진행함 | 2차 뒤 `pytest -k P7` 통과 |
| IAM-03-04 | 기존 `register-ssm-params.sh`를 실행 경로에서 참조하지 않음 | 검사 결과 참조 0건 |

## IAM-04 앱 시크릿 잔여 항목 결정·적용

**목적:** 아직 일반 문자열로 저장된 앱 시크릿 2개의 암호화 저장(SecureString) 전환 여부를 정함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | IAM-03 | 앱 시크릿 SecureString 범위 | Phase 2 1차 | 신규 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| IAM-04-01 | DB 접속 주소·DB 사용자명 파라미터의 전환 여부를 운영진 승인으로 확정 | decisions.md 상태 "결정 완료" |
| IAM-04-02 | 2026-10-03 "현행 유지, 후속 이슈로 분리"로 결정됨. 전환은 Phase 2 밖 후속 이슈에서 진행함. 후속 이슈의 선행 확인 항목은 백엔드 `load-ssm-env.sh` 영향과 EC2 역할 KMS 권한임 | 후속 이슈 생성, 이 티켓은 결정 기록 확인으로 종료 |

---

## 확인 필요 사항

- 전환하면 백엔드 `load-ssm-env.sh` 동작에 영향이 있는지 [확인 필요: 백엔드 리드]
- Terraform 실행 자격 증명: 로컬은 `aws login` 세션(장기 액세스 키 아님), CI는 GitHub OIDC plan 역할로 확정(2026-10-02, decisions.md "Terraform 실행 자격 증명")
