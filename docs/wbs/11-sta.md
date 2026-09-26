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

> 진행: STA-01-01은 PR #9로 완료(머지). STA-01-03(그룹별 파일)이 남음.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | 없음 | 없음 | MS1 | 2.1 | #7, PR #9 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-01-01 | `bootstrap/`, `envs/prod/`, `modules/` 하위 8개, `docs/`, `.github/workflows/`, `scripts/`, `tests/` 생성 | `find` 결과에 폴더 모두 존재 |
| STA-01-02 | 계정 ID·리전·자원 ID를 코드에 직접 쓰지 않았는지 검사 | 저장소 전체 검색 결과에 계정 ID 패턴 없음 |
| STA-01-03 | `envs/prod`를 그룹별 파일(`network.tf`, `iam.tf` … `deploy.tf`)과 `imports/` 폴더로 나누고 빈 파일을 미리 만들어 둠. 공통 파일(`versions.tf`, `providers.tf`, `backend.tf`)은 STA 담당만 수정 | `envs/prod`에 그룹 파일 8개와 `imports/` 존재 |

## STA-02 버전·provider 규칙

**목적:** Terraform·AWS provider 버전과 리전 설정을 고정함

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-01 | 없음(DOC-04에서 버전 정정) | MS1 | 2.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-02-01 | Terraform `>= 1.11.0, < 2.0.0`, AWS provider 버전 범위 지정 | `versions.tf`에 값 존재, `terraform version` 결과가 범위 안 |
| STA-02-02 | 기본 서울 리전 provider와 CloudFront 인증서 조회용 us-east-1 provider 구성 | `providers.tf`에 두 provider 블록 존재 |
| STA-02-03 | `.terraform.lock.hcl` 생성·커밋 | `terraform providers lock` 실행 후 파일이 git에 추가됨 |

## STA-03 state 버킷 구현

**목적:** state를 저장할 전용 S3 버킷을 보호 설정과 함께 만듦

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-02 | state 버킷·키 | MS1 | 3.1 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-03-01 | 버전 관리·암호화·퍼블릭 액세스 차단 적용 | `aws s3api get-bucket-versioning`·`get-bucket-encryption`·`get-public-access-block` 결과 모두 활성 |
| STA-03-02 | 버킷과 보호 설정 전부에 `prevent_destroy` 적용 | 삭제하는 plan을 만들면 오류로 차단됨 |
| STA-03-03 | DynamoDB 잠금 테이블을 만들지 않음(S3 자체 잠금 사용) | 코드 검색에서 `dynamodb_table` 없음 |

## STA-04 envs/prod backend 초기화

**목적:** 운영 환경 코드가 STA-03 버킷에 state를 저장하도록 연결함

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-03 | state 버킷·키 | MS1 | 3.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-04-01 | backend 설정에 `use_lockfile = true`만 사용 | `backend.tf`에 해당 값 존재, `dynamodb_table` 없음 |
| STA-04-02 | bootstrap 완료 전에는 envs/prod 초기화가 실패하도록 함 | bootstrap 전 `terraform init` 실행 시 명확한 오류 |

## STA-05 PR CI(fmt·validate·plan)

**목적:** PR마다 형식·문법 검사와 plan을 자동 실행하고 결과를 PR에 남김

> 진행: `.github/workflows/ci.yml`에 AWS 권한 없이 도는 `fmt -check`·`init -backend=false`·`validate`·tflint가 이미 있음(PR #3). 남은 것은 plan 실행·PR 코멘트·OIDC 연결.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-02 | 없음(브랜치 전략 해소: dev → main) | MS1 | 7.4 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-05-01 | `terraform fmt -check`, `validate`, plan 실행 후 결과를 PR 코멘트로 게시 | 샘플 PR에 자동 코멘트 확인 |
| STA-05-02 | 세 검사가 모두 성공해야 apply 대상으로 표시 | 검사 하나를 일부러 실패시키면 표시되지 않음 |
| STA-05-03 | GitHub OIDC 인증 사용, 장기 액세스 키 사용 안 함 | workflow에 `id-token: write` 존재, 저장소 시크릿에 액세스 키 없음 |

## STA-06 property 테스트 실행 환경

**목적:** 설계 문서의 검증 속성(P1~P10) 테스트를 돌릴 Python 환경을 만듦

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-01 | 없음 | MS1 | 신규 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-06-01 | hypothesis 라이브러리 설치, 테스트당 100회 이상 실행 설정 | `pytest tests/property/` 실행 성공 |

## STA-07 안전 게이트 + P1·P6

**목적:** import를 시작하기 전에 삭제·교체·시크릿 노출을 막는 검사를 만듦. MS2a 모든 그룹의 시작 조건

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | STA-04, STA-06 | 없음 | MS1 | 5.3, 8.1, 8.3 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-07-01 | plan 결과(JSON)에서 보호 자원(RDS·EC2·EIP와 연결·CloudFront·Route53 레코드·S3)의 삭제·교체가 나오면 차단 | 보호 자원마다(EIP 포함) 일부러 교체·삭제를 일으키는 변경에서 검사 실패 |
| STA-07-02 | RDS 비밀번호 변경이나 시크릿 실제 값이 plan에 나오면 차단 | 시크릿 테스트 값으로 실행 시 원문이 출력에 없음 |
| STA-07-03 | 보안 그룹 규칙의 과도한 변경만 골라서 차단(다른 자원 변경은 통과) | 보안 그룹 규칙만 바꾼 plan은 차단, 그 외는 통과 |
| STA-07-04 | P1 테스트: 보호 자원은 교체되지 않음 | `pytest -k P1` 통과 |
| STA-07-05 | P6 테스트: 시크릿 값이 출력되지 않음 | `pytest -k P6` 통과 |

## STA-08 그룹 간 연결 점검

**목적:** 그룹별 파일로 나눠 작성된 모듈이 서로 output으로 올바르게 연결됐는지 점검함. 각 그룹이 자기 파일에서 연결하므로 이 티켓은 점검과 누락 보완만 함

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | CMP-03, RDB-01, CDN-03, DEP-02 | 없음 | MS2b | 5.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-08-01 | 그룹 간 참조가 network → iam·params·storage·compute·database → cdn·deploy 방향으로만 이어지고 순환이 없는지 확인 | `terraform graph`에 순환 없음, `terraform validate` 통과 |
| STA-08-02 | ALB 주소·EC2-A origin·서브넷 ID 등을 손으로 입력하지 않고 다른 그룹 output에서 받아 씀 | 코드에 직접 적은 DNS·ID 문자열 없음 |

## STA-09 최종 일치 확인 + P2

**목적:** 모든 그룹의 plan이 "No changes"인지 확인하는 절차를 만듦. MS2b 완료 조건

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-08 | 없음 | MS2b | 6.9, 8.6 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-09-01 | 그룹별 plan이 "No changes"이거나 승인된 신규 자원만 있을 때만 통과 | `terraform show -json`의 `resource_changes`가 비었거나 승인 목록과 일치 |
| STA-09-02 | P2 검사: import 결과가 조사 내용과 일치 | `pytest tests/integration/test_import_convergence.py` 통과 |

## STA-10 배포 workflow 계약 검사 + P8

**목적:** 기존 backend·frontend 배포 workflow가 쓰는 이름·ARN이 Terraform output과 같은지 검사함

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-08, DEP-02 | 없음 | MS3 | 7.3, 8.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-10-01 | backend `cd.yml`, frontend 배포 workflow의 참조 값과 output 비교. 비교 대상은 이름·ARN만(#13 R3 배포 방식 변경과 충돌 방지) | 검사 스크립트 결과 불일치 0건 |
| STA-10-02 | P8 테스트: 값 하나라도 다르면 실패 | 값을 일부러 바꾸면 테스트 실패 |

## STA-11 승인 후 apply

**목적:** main 머지 뒤 승인자가 승인해야 apply가 실행되도록 함

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-10 | apply 승인자 | MS3 | 7.5 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-11-01 | GitHub Environment 승인 전에는 apply 실행 안 함 | 승인 없이 머지하면 apply 작업이 대기 상태로 멈춤 |
| STA-11-02 | plan용 읽기 롤과 apply용 쓰기 롤 분리 | 두 workflow가 서로 다른 롤을 사용(실제 ARN은 비공개 변수) |

## STA-12 drift 감지 CI + P9

**목적:** 매일 plan을 읽기 전용으로 돌려 코드와 실제가 달라졌는지 알림

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | STA-11 | 없음 | MS3 | 7.6, 8.9 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-12-01 | 24시간마다 최소 1회 읽기 전용 plan 실행 | workflow 예약 설정과 실행 이력 확인 |
| STA-12-02 | P9 검사: 장기 액세스 키 0건, OIDC 권한 설정 | `pytest tests/static/test_ci_security.py` 통과 |

## STA-13 정적·통합 검증 구성

**목적:** 형식·문법·잠금 파일·직접 입력된 ID 검사를 CI 한 곳에 모음

> 진행: fmt·validate·tflint는 `ci.yml`에 있음. 남은 것은 잠금 파일 체크섬과 직접 입력 ID 검사.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | SEA-02, SEA-03, STA-12 | 없음 | MS3 | 8.11 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| STA-13-01 | `terraform fmt -check -recursive`, `init -backend=false`, `validate`, 잠금 파일 체크섬, 직접 입력 ID 검사 구성 | CI 로그에 전체 명령 결과 존재 |

---

## 확인 필요 사항

- property 테스트 범위: 설계대로 hypothesis 테스트 유지 vs plan 검사 스크립트와 고정 입력 테스트 몇 개로 축소 [확인 필요]
- AWS provider 6.x 사용 여부 [추정: 신규 저장소는 6.x로 시작 권장, 공식 문서 확인 필요]
- apply 승인자 1~2명 [확인 필요]
