# STA state·CI 기반 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- Terraform state를 안전하게 저장할 곳을 만듦
- 운영 apply 전에 반드시 통과해야 하는 검사(삭제·교체 차단, 시크릿 비노출, 배포 계약 일치)를 자동화함
- PR 검사, 승인 후 apply, drift 감지 CI 3종을 만듦

**범위:** 저장소 구조, bootstrap, envs/prod backend, 안전 게이트, 모듈 연결, CI workflow, property 테스트 실행 환경
**범위 밖:** 각 자원 그룹 코드(→ NET·IAM·STO·CMP·RDB·CDN·DEP 명세서)

---

## STA-01 저장소 디렉터리 구조

**목적:** 설계 문서에 정한 폴더 구조를 만듦

> 진행: 완료. STA-01-01은 #7(PR #9), STA-01-02는 #16(PR #17)의 민감 정보 검사로 충족, STA-01-03은 #23.

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | 없음 | 없음 | Phase 1 | 2.1 | #7, #23 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-01-01 | `bootstrap/`, `envs/prod/`, `modules/` 하위 8개, `docs/`, `.github/workflows/`, `scripts/`, `tests/` 생성 | `find` 결과에 폴더 모두 존재 |
| STA-01-02 | 계정 ID·리전·자원 ID를 코드에 직접 쓰지 않았는지 검사 | 저장소 전체 검색 결과에 계정 ID 패턴 없음 |
| STA-01-03 | `envs/prod`를 그룹별 파일(`network.tf`, `iam.tf` … `deploy.tf`)과 그룹별 import 파일(`imports_network.tf` … `imports_deploy.tf`)로 나누고 빈 파일을 미리 만들어 둠. import 블록은 root 모듈 바로 아래 파일에만 둘 수 있어 하위 폴더를 쓰지 않음. 공통 파일(`versions.tf`, `providers.tf`, `backend.tf`)은 STA 담당만 수정 | `envs/prod`에 그룹 파일 8개와 `imports_<그룹>.tf` 8개 존재 |

## STA-02 버전·provider 규칙

**목적:** Terraform·AWS provider 버전과 리전 설정, tflint 규칙을 고정함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-01 | 없음(DOC-04에서 버전 정정) | Phase 1 | 2.2 | #24 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-02-01 | Terraform `>= 1.11.0, < 2.0.0`, AWS provider 버전 범위 지정 | `versions.tf`에 값 존재, `terraform version` 결과가 범위 안 |
| STA-02-02 | 기본 서울 리전 provider와 CloudFront 인증서 조회용 us-east-1 provider 구성. envs/prod는 `default_tags` 없이 둠(적용은 STA-09 뒤 태그 전용 PR), bootstrap은 처음부터 적용 | `providers.tf`에 두 provider 블록 존재 |
| STA-02-03 | `.terraform.lock.hcl` 생성·커밋 | `terraform providers lock` 실행 후 파일이 git에 추가됨 |
| STA-02-04 | `.tflint.hcl` 작성: AWS 규칙 묶음 사용, `terraform_documented_variables`·`terraform_documented_outputs` 켜기(모든 variable·output에 `description` 필수). CI의 `tflint_version: latest`를 고정 버전으로 교체 | `description` 없는 variable을 넣으면 tflint 실패, `ci.yml`에 `latest` 없음 |

> 진행: 완료(#24). Terraform `>= 1.11.0`, AWS provider 6.x(잠금 6.66.0), 잠금 파일은 root마다(envs/prod, bootstrap) linux_amd64·darwin_arm64·darwin_amd64 체크섬 포함. tflint 0.64.0·aws 규칙 0.49.0, CI에서 플러그인 설치 실패를 무시하지 않도록 수정

## STA-03 state 버킷 구현

**목적:** state를 저장할 전용 S3 버킷을 보호 설정과 함께 만듦

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-02 | state 버킷·키 | Phase 1 | 3.1 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-03-01 | 버전 관리·암호화·퍼블릭 액세스 차단 적용 | `aws s3api get-bucket-versioning`·`get-bucket-encryption`·`get-public-access-block` 결과 모두 활성 |
| STA-03-02 | 버킷과 보호 설정 전부에 `prevent_destroy` 적용 | 삭제하는 plan을 만들면 오류로 차단됨 |
| STA-03-03 | DynamoDB 잠금 테이블을 만들지 않음(S3 자체 잠금 사용) | 코드 검색에서 `dynamodb_table` 없음 |

> 진행: 완료(#25). 2026-09-27 bootstrap apply(추가 7, 변경·삭제 0). SSE-S3(AES256), `BucketOwnerEnforced`, TLS 강제 정책, lifecycle 3개 추가. provider에 `allowed_account_ids` 계정 가드. bootstrap state는 같은 버킷 `bootstrap/terraform.tfstate`로 이전. 버킷 이름은 `docs/records/inventory.md`

## STA-04 envs/prod backend 초기화

**목적:** 운영 환경 코드가 STA-03 버킷에 state를 저장하도록 연결함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-03 | state 버킷·키 | Phase 1 | 3.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-04-01 | backend 설정에 `use_lockfile = true`만 사용 | `backend.tf`에 해당 값 존재, `dynamodb_table` 없음 |
| STA-04-02 | bootstrap 완료 전에는 envs/prod 초기화가 실패하도록 함 | bootstrap 전 `terraform init` 실행 시 명확한 오류 |

> 진행: 완료(#26). 2026-09-27 init 성공·plan "No changes". backend 설정 없이 init, 버킷 없이 init 모두 오류로 실패 확인. 승인 대기 중인 apply가 잠금을 잡은 상태에서 동시 plan이 차단됨 확인. provider 두 개와 backend에 `allowed_account_ids` 계정 가드, 다른 계정 자격 증명은 plan 단계에서 실패. 팀원용 로컬 준비·force-unlock 절차는 `docs/guides/import-procedure.md` 0절·2절

## STA-05 PR CI(fmt·validate·plan)

**목적:** PR마다 형식·문법 검사와 plan을 자동 실행하고 결과를 PR에 남김

> 진행: 코드 완료(#31), 운영 반영 대기.
> - `ci.yml`에 plan 작업(`Terraform Plan (envs/prod)`)과 집계 작업(`Apply Ready`) 추가. Apply Ready는 민감 정보·gitleaks·fmt·validate·tflint·plan이 모두 성공해야 초록(STA-05-02)
> - plan 역할: `bootstrap/ci_plan_role.tf`. 기존 GitHub OIDC provider를 참조(IAM 그룹이 import 예정), 이 저장소 `pull_request` 토큰만 허용, ReadOnlyAccess + state 조회·`.tflock` 쓰기, S3 객체(state 제외)·복호화·시크릿·로그 읽기 명시 거부
> - 공개 저장소라 plan 원문·plan JSON은 출력·업로드하지 않음. `scripts/plan_summary.py`가 개수와 자원 주소만 요약하고 오류 로그는 식별자를 가림(검사: `tests/static/test_plan_summary.py`)
> - 모든 workflow의 `uses:`를 커밋 SHA로 고정. `pull_request_target`은 plan workflow에서 쓰지 않음. 기존 제목·base 검사·자동 라벨 workflow는 코드를 checkout하지 않는 github-script만 실행해 유지
> - 남은 것: bootstrap apply(운영 승인), 저장소 secret 3개(`AWS_PLAN_ROLE_ARN`, `TF_STATE_BUCKET`, `AWS_ACCOUNT_ID`) 등록, 샘플 PR에서 코멘트·Apply Ready 확인. 그 전까지 plan은 건너뛰고 Apply Ready는 skipped
> - plan 역할은 `kms:Decrypt`를 거부함. 설계상 앱 시크릿(SecureString)은 값 관리 대상이 아니고(requirements.md Secret_Parameter, design.md "값 소유 resource로 만들지 않는다"), IAM-03이 import하는 `/boaz/infra/*` 12개는 String이라 복호화가 필요 없음. 앱 시크릿을 `aws_ssm_parameter`로 import하면 plan이 권한 오류로 실패하고 안전 게이트(G2)도 막음. 존재·타입 확인 방법은 `docs/wbs/22-iam.md` IAM-03 참고

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-02 | 없음(브랜치 전략 해소: dev → main) | Phase 2 준비 | 7.4 | #31 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-05-01 | `terraform fmt -check`, `validate`, plan 실행 후 결과를 PR 코멘트로 게시 | 샘플 PR에 자동 코멘트 확인 |
| STA-05-02 | 세 검사가 모두 성공해야 apply 대상으로 표시 | 검사 하나를 일부러 실패시키면 표시되지 않음 |
| STA-05-03 | GitHub OIDC 인증 사용, 장기 액세스 키 사용 안 함 | workflow에 `id-token: write` 존재, 저장소 시크릿에 액세스 키 없음 |
| STA-05-04 | `pull_request_target` 트리거를 쓰지 않음. checkout은 `persist-credentials: false`. 외부 액션은 커밋 SHA로, 설치 도구는 버전으로 고정(`latest` 금지) | workflow에 `pull_request_target`·`latest` 없음, `uses:`가 SHA로 고정 |

## STA-06 property 테스트 실행 환경

**목적:** 설계 문서의 검증 속성(P1~P10) 테스트를 돌릴 Python 환경을 만듦

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-01 | 없음 | Phase 2 준비 | 신규 | #32 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-06-01 | hypothesis 라이브러리 설치, 테스트당 100회 이상 실행 설정 | `pytest tests/property/` 실행 성공 |

> 진행: 완료(#32). `tests/requirements.in`(pytest·hypothesis 고정) → 해시 잠금 `tests/requirements.txt`, pytest 설정 `pyproject.toml`(testpaths `tests/static`·`tests/property`), hypothesis 프로필 `tests/property/conftest.py`(기본 `ci` 100회·derandomize, `thorough` 1000회). 환경 자체 검사 `tests/property/test_harness.py`. CI `Python Tests` 작업이 실행하고 `Apply Ready` 조건에 포함. 결정 "property 테스트 범위"는 대기 상태라 권장안(판정 로직은 고정 입력 테스트, hypothesis는 P1·P6)으로 선행 구현함

## STA-07 안전 게이트 + P1·P6

**목적:** import를 시작하기 전에 삭제·교체·시크릿 노출을 막는 검사를 만듦. Phase 2 1차 모든 그룹의 시작 조건

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | STA-04, STA-06 | 없음 | Phase 2 준비 | 5.3, 8.1, 8.3 | #33 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-07-01 | plan 결과(JSON)에서 보호 자원(RDS·EC2·EIP와 연결·CloudFront·Route53 레코드·S3)의 삭제·교체가 나오면 차단 | 보호 자원마다(EIP 포함) 일부러 교체·삭제를 일으키는 변경에서 검사 실패 |
| STA-07-02 | RDS 비밀번호 변경이나 시크릿 실제 값이 plan에 나오면 차단 | 시크릿 테스트 값으로 실행 시 원문이 출력에 없음 |
| STA-07-03 | 보안 그룹 규칙의 과도한 변경만 골라서 차단(다른 자원 변경은 통과) | 보안 그룹 규칙만 바꾼 plan은 차단, 그 외는 통과 |
| STA-07-04 | P1 테스트: 보호 자원은 교체되지 않음 | `pytest -k P1` 통과 |
| STA-07-05 | P6 테스트: 시크릿 값이 출력되지 않음 | `pytest -k P6` 통과 |

> 진행: 코드 완료(#33), 실제 plan 연동 확인은 STA-05 운영 반영(bootstrap apply·secret 등록) 뒤.
> - `scripts/plan_gate.py`: plan JSON 검사. G1 보호 자원(`aws_db_instance`·`aws_instance`·`aws_eip`·`aws_eip_association`·`aws_cloudfront_distribution`·`aws_route53_record`·`aws_route53_zone`·`aws_s3_bucket`) 삭제·교체, G2 RDS 비밀번호 설정·변경·SecureString/Secrets Manager 값을 state에 저장하는 설정·sensitive output, G3 `0.0.0.0/0`·`::/0`에 80·443 외 포트를 여는 inbound 규칙 추가·변경. import-only(no-op)와 그 외 변경은 통과. 출력에는 규칙·주소(마스킹)·사유만
> - CI plan 작업에서 요약 뒤에 실행하고, 차단이면 plan 작업 실패 → `Apply Ready` 실패. PR 코멘트 제목이 "안전 게이트 차단"으로 바뀜
> - 테스트: 고정 입력 `tests/static/test_plan_gate.py`(보호 자원 8종 × 삭제·교체 2순서, 통과 사례 포함), property `tests/property/test_design_invariants.py`의 P1·P6(각 100회). 규칙을 일부러 빼거나 약하게 바꾸면 테스트가 실패하는 것 확인
> - 2026-10-03 G4 추가: Phase 2 동안 보호 자원 밖 자원의 삭제·교체도 차단(removed 블록의 forget은 통과). 관리자 로컬 apply 직전에도 같은 게이트 실행을 필수로 함(decisions.md "Phase 2 게이트 범위", import-procedure.md 2절). 테스트: 고정 입력 G4 사례, P1을 "게이트 통과 = 어떤 자원에도 delete 없음"으로 확장
> - 승인된 예외(예: 보안 그룹 규칙 변경 승인)로 게이트를 넘기는 방법은 없음. 필요하면 STA-11(승인 후 apply)에서 GitHub Environment 승인과 함께 설계

## STA-08 그룹 간 연결 점검

**목적:** 그룹별 파일로 나눠 작성된 모듈이 서로 output으로 올바르게 연결됐는지 점검함. 각 그룹이 자기 파일에서 연결하므로 이 티켓은 점검과 누락 보완만 함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | CMP-03, RDB-01, CDN-03, DEP-02 | 없음 | Phase 2 마무리 | 5.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-08-01 | 그룹 간 참조가 network → iam·params·storage·compute·database → cdn·deploy 방향으로만 이어지고 순환이 없는지 확인 | `terraform graph`에 순환 없음, `terraform validate` 통과 |
| STA-08-02 | ALB 주소·EC2-A origin·서브넷 ID 등을 손으로 입력하지 않고 다른 그룹 output에서 받아 씀 | 코드에 직접 적은 DNS·ID 문자열 없음 |

## STA-09 최종 일치 확인 + P2

**목적:** 모든 그룹의 plan이 "No changes"인지 확인하는 절차를 만듦. Phase 2 완료 조건

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-08 | 없음 | Phase 2 마무리 | 6.9, 8.6 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-09-01 | 그룹별 plan이 "No changes"이거나 승인된 신규 자원만 있을 때만 통과 | `terraform show -json`의 `resource_changes`가 비었거나 승인 목록과 일치 |
| STA-09-02 | P2 검사: import 결과가 조사 내용과 일치 | `pytest tests/integration/test_import_convergence.py` 통과 |

## STA-10 배포 workflow 계약 검사 + P8

**목적:** 기존 backend·frontend 배포 workflow가 쓰는 이름·ARN이 Terraform output과 같은지 검사함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-08, DEP-02 | 없음 | Phase 3 | 7.3, 8.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-10-01 | backend `cd.yml`, frontend 배포 workflow의 참조 값과 output 비교. 비교 대상은 이름·ARN만(#13 R3 배포 방식 변경과 충돌 방지) | 검사 스크립트 결과 불일치 0건 |
| STA-10-02 | P8 테스트: 값 하나라도 다르면 실패 | 값을 일부러 바꾸면 테스트 실패 |

## STA-11 승인 후 apply

**목적:** main 머지 뒤 승인자가 승인해야 apply가 실행되도록 함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-10 | apply 승인자 | Phase 3 | 7.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-11-01 | GitHub Environment 승인 전에는 apply 실행 안 함 | 승인 없이 머지하면 apply 작업이 대기 상태로 멈춤 |
| STA-11-02 | plan용 읽기 롤과 apply용 쓰기 롤 분리 | 두 workflow가 서로 다른 롤을 사용(실제 ARN은 비공개 변수) |
| STA-11-03 | 롤 신뢰 조건(OIDC `sub`)을 이 저장소의 `main` 브랜치·`prod` environment로 정확히 고정(와일드카드 금지). apply는 `main` push에서만 실행 | 다른 브랜치·PR에서 apply 롤을 요청하면 거부됨 |

## STA-12 drift 감지 CI + P9

**목적:** 매일 plan을 읽기 전용으로 돌려 코드와 실제가 달라졌는지 알림

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-11 | 없음 | Phase 3 | 7.6, 8.9 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-12-01 | 24시간마다 최소 1회 읽기 전용 plan 실행 | workflow 예약 설정과 실행 이력 확인 |
| STA-12-02 | P9 검사: 장기 액세스 키 0건, OIDC 권한 설정 | `pytest tests/static/test_ci_security.py` 통과 |

## STA-13 정적·통합 검증 구성

**목적:** 형식·문법·잠금 파일·직접 입력된 ID 검사를 CI 한 곳에 모음

> 진행: fmt·validate·tflint는 `ci.yml`에 있음. 남은 것은 잠금 파일 체크섬과 직접 입력 ID 검사.

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | SEA-02, SEA-03, STA-12 | 없음 | Phase 4 | 8.11 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-13-01 | `terraform fmt -check -recursive`, `init -backend=false`, `validate`, 잠금 파일 체크섬, 직접 입력 ID 검사 구성 | CI 로그에 전체 명령 결과 존재 |

---

## 확인 필요 사항

- property 테스트 범위: 설계대로 hypothesis 테스트 유지 vs plan 검사 스크립트와 고정 입력 테스트 몇 개로 축소 [확인 필요]
- AWS provider 6.x 사용 여부: 6.x로 확정(결정 레지스터 "AWS provider 버전", #24)
- apply 승인자 1~2명 [확인 필요]
