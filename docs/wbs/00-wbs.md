# product-infra Terraform 이전 WBS

| 기준일 | 근거 | 성격 |
| --- | --- | --- |
| 2026-09-26 | `docs/overview/migration-plan.md`(배경·원칙), `.kiro/specs/product-infra-migration/`(초기 설계 참고) | 실행 계획. 날짜·담당은 팀 확인 전까지 기준선 |

> 운영 중인 AWS 인프라(수동 구축 + 셸 스크립트)를 Terraform 코드로 옮기는 작업 전체를 명세서 12개, 티켓 57개로 나눈 문서.
> 12월 모집 시즌 전 목표는 **평시(off) 상태의 모든 자원을 import하고 `terraform plan` 결과가 "No changes"인 상태**까지. 시즌 전환 자동화와 리허설은 2027년으로 넘긴다.

---

## 읽는 법

### 규모

학기 중 학생 운영진 기준. 시험·프로젝트 마감이 끼는 것을 전제로 한다.

| 규모 | 뜻 |
| --- | --- |
| 하루이틀 | 1~2일 안에 끝나는 작업 |
| 한 주 | 1주 정도 걸리는 작업 |
| 2~3주 | 2~3주 걸리는 작업 |
| 한 달 이상 | 한 달 넘게 걸리는 작업(현재 해당 티켓 없음) |

### 번호 규칙

| 구분 | 형식 | 명세서에서의 위치 | 예시 |
| --- | --- | --- | --- |
| 명세서 | 영문 대문자 3글자 접두사 | 문서 1개 | `NET` 네트워크 명세서 |
| 티켓 키 | `접두사-두 자리` | 명세서의 **화면** | `NET-01` |
| 기능 ID | `티켓 키-두 자리` | 명세서의 **기능** | `NET-01-01` |

- 티켓 1개 = GitHub 이슈 1개, PR 1개 정도로 닫을 수 있는 단위.
- 기능 ID마다 "완료 확인 방법"이 있다. 실행 명령 결과나 산출물로 확인할 수 있어야 완료로 본다.
- `P1`~`P10`은 설계 문서(design.md)의 검증 속성 번호. 독립 마일스톤으로 두지 않고 해당 티켓의 기능으로 넣었다.

### 문서 역할과 우선순위

| 문서 | 역할 |
| --- | --- |
| 노션 WBS·명세서(이 문서) | 기준 문서(확정). 티켓 단위 완료 조건과 GitHub 이슈 연결 |
| `tasks.md` | 구현 순서·의존성·요구사항 추적용 보조 문서. 노션과 다르면 노션 기준으로 맞춤 |
| `import-log.md` | 그룹별 import 대상·plan 결과 기록 |
| `decisions.md` | 결정 기록 |

- PR은 GitHub 이슈(티켓 단위)와 연결한다. 기능 ID는 명세서 안에서 완료 여부를 확인하는 단위로 쓴다.
- 12월 전에는 import 대상 명세서(NET·IAM·STO·CMP·RDB·CDN·DEP)와 `import-log.md`를 우선 정확하게 관리하고, 나머지 명세서는 해당 마일스톤에 가까워지면 보강한다.
- 남는 시간은 시즌 전환·롤백·장애 대응 런북에 먼저 쓴다.

### 명세서 목록

페이지 번호 묶음: 0x 모두가 먼저 읽는 페이지 · 1x 사전 준비(인프라 리드) · 2x MS2a 그룹 · 3x MS2b 그룹 · 4x 2027년 이후

| 접두사 | 명세서 | 범위 | 마일스톤 | 페이지 |
| --- | --- | --- | --- | --- |
| (공통) | 그룹 import 공통 절차 | 파일 규칙, apply 순서, 작업 9단계, 멈춤 조건, PR 리뷰 체크리스트 | MS2a, MS2b | guides/import-procedure.md |
| DOC | 문서·스펙 정리 | 문서 상태 오기 정정, 결정 레지스터 통합, 스펙 결함 정정, README·런북·계약 문서 | MS0, MS4 | 10-doc.md |
| STA | state·CI 기반 | 저장소 구조, state 저장소, 안전 게이트, PR·apply·drift CI, 자동 검증 | MS1, MS2b, MS3 | 11-sta.md |
| OBS | 모니터링·경보 | CloudWatch Agent, SNS 경보, 접근 로그·대시보드 | MS1, MS3 | 12-obs.md |
| NET | 네트워크 | VPC, 서브넷, 라우팅, 보안 그룹 | MS2a | 20-net.md |
| IAM | 권한·파라미터 | IAM 롤·정책·OIDC, SSM 인프라 파라미터, 앱 시크릿 | MS2a | 21-iam.md |
| STO | 스토리지 | S3 버킷 | MS2a | 22-sto.md |
| CMP | 서버 | EC2-A/B, Elastic IP, Target Group, ALB | MS2b | 30-cmp.md |
| RDB | 데이터베이스 | RDS 인스턴스, 서브넷 그룹, 파라미터 그룹 | MS2b | 31-rdb.md |
| CDN | CloudFront·Route53·ACM·WAF | CloudFront 배포 3개(api·www·admin), DNS, 인증서, WAF 연결 | MS2b, MS3 | 32-cdn.md |
| DEP | CodeDeploy | 배포 앱·배포 그룹·서비스 롤, 기존 배포 설정 보존 | MS2b | 33-dep.md |
| SEA | 시즌 전환 | 시즌 on/off 변수 모델, 시즌 시작·종료 순서 제어 | MS2b, MS3 | 40-sea.md |
| OPS | 운영 절차 | 12월 동결, 시즌 직후 검증, 2027-01 동결, 리허설, 최종 인수, 구 스크립트 정리 | 동결 ~ MS4 | 41-ops.md |

### 용어

| 용어 | 뜻 |
| --- | --- |
| import | 이미 AWS에 있는 자원을 Terraform state에 등록해 코드로 관리하기 시작하는 절차. 자원을 새로 만들거나 지우지 않음 |
| plan | 코드와 실제 자원을 비교해 무엇이 바뀔지 미리 보여 주는 명령. "No changes"는 코드와 실제가 완전히 같다는 뜻 |
| apply | plan에 나온 변경을 실제 AWS 자원에 반영하는 명령 |
| state | Terraform이 관리 중인 자원의 현재 구성을 기록한 파일. 손상·유출 시 사고가 가장 큰 지점 |
| prevent_destroy | 자원을 지우거나 새로 만들어 바꾸는(교체) 계획이 나오면 apply 자체를 막는 설정 |
| drift | 콘솔 수동 변경 등으로 실제 자원이 코드와 달라진 상태 |
| season_capacity | 시즌 용량 변수(`off`/`on`). ALB·listener, EC2-B 기동과 기능 태그, Target Group 등록 대상, RDS Multi-AZ를 제어 |
| api_origin | api CloudFront origin 변수(`ec2`/`alb`). `alb`는 `season_capacity = on`일 때만 허용 |
| 그룹 | import를 함께 진행하는 자원 묶음. network, iam, params, storage, compute, database, cdn, deploy 8개 |

---

## 진행 현황 (2026-09-26 기준)

| 구분 | 내용 | 근거 | 상태 |
| --- | --- | --- | --- |
| 저장소 자동화 | 이슈·PR 템플릿, 커밋 훅, PR 제목·base 검사, 자동 라벨·배정, CI(fmt·validate·tflint) | #1, PR #3 | 완료(머지) |
| 초기 설계 문서 | `.kiro` 스펙(requirements·design·tasks), 이전 계획서, 현행 인프라 스펙 | #2, PR #4 | 완료(머지) |
| 자동 코드 리뷰 | CodeRabbit 설정 | #5, PR #6 | 완료(머지) |
| 저장소 폴더 구조 | `bootstrap/`, `envs/prod/`, `modules/*`, `tests/*`, `.gitignore` | #7, PR #9 | 작업 완료, 리뷰 대기 → DOC-05 |
| AWS 운영 자원 조사 | inventory·decisions·import-log 문서 3종(tasks.md 1.1~1.3) | #8, PR #10 | 작업 완료, 리뷰 대기 → DOC-05 |
| 구 WBS 문서 | `docs/wbs.md` | #11, PR #12 | `docs/wbs/`로 대체, 닫을 예정 → DOC-01 |
| 관리자 콘솔 인프라 요구사항 | 요구사항 정리(R1~R18) | #13 | 열린 상태 유지. 인프라 범위 항목은 이 WBS에 반영 |

- 이 표의 "완료" 항목은 티켓으로 만들지 않았다. 부분 완료 티켓(STA-01, STA-05, STA-13, DOC-03)은 각 명세서에 진행 내용을 적었다.

## 담당 구분

| 구간 | 계획서 단계 | 담당 | 티켓 |
| --- | --- | --- | --- |
| 사전 준비 | Phase 0~1 (조사, 저장소 구조, state 저장소) | 인프라 리드 1명 | DOC-01~07, STA-01~04 |
| 그룹 import | Phase 2 (리소스 그룹 단위 import) | 팀원이 그룹별로 분담 | 아래 배정표 |
| 담당 미정 | Phase 2 시작 전·중에 필요 | [확인 필요] | STA-05, STA-06, STA-07, OBS-01, SEA-01, STA-08, STA-09 |

- STA-05(PR CI)·STA-06·STA-07(안전 게이트)은 Phase 2 첫 PR 전에 끝나 있어야 한다. 없으면 팀원 PR에서 plan 결과 자동 확인과 교체·삭제 차단이 동작하지 않는다.
- SEA-01은 컴퓨팅·DB 그룹 시작 전에, STA-08·09는 모든 그룹 완료 후에 필요하다.

## import 그룹 배정표

> 이전 계획서의 Phase 2 그룹 8개와 명세서·티켓 대응. 팀원에게 그룹을 나눠 줄 때 이 표의 담당 칸을 채운다.
> 모든 그룹은 공통 절차(`docs/guides/import-procedure.md`)를 따른다. 파일은 그룹마다 따로 있으므로 서로 다른 그룹은 동시에 작업해도 코드 충돌이 없다. apply는 한 번에 한 그룹만.

| 순서 | 계획서 그룹 | 명세서 | 티켓 | 수정 파일(`envs/prod/`) | 선행 | 담당 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 네트워크 | NET | NET-01 | `network.tf` | STA-07 | [확인 필요] |
| 2 | IAM | IAM | IAM-01, IAM-02 | `iam.tf` | STA-07 | [확인 필요] |
| 2 | SSM 파라미터 | IAM | IAM-03, IAM-04 | `params.tf` | IAM-01 | [확인 필요] |
| 3 | 스토리지 | STO | STO-01, STO-02 | `storage.tf` | STA-07 | [확인 필요] |
| 4 | 컴퓨팅(EC2·EIP) | CMP | CMP-01 | `compute.tf` | SEA-01, IAM-02 | [확인 필요] |
| 5 | DB | RDB | RDB-01 | `database.tf` | SEA-01, NET-01 | [확인 필요] |
| 6 | 로드밸런싱(Target Group·ALB) | CMP | CMP-02, CMP-03 | `compute.tf`(CMP-01 담당이 이어서) | CMP-01 | [확인 필요] |
| 7 | CDN·DNS·인증서 | CDN | CDN-01, CDN-02 | `cdn.tf` | CMP-02 | [확인 필요] |
| 8 | 배포(CodeDeploy) | DEP | DEP-01, DEP-02 | `deploy.tf` | IAM-02, STO-01 | [확인 필요] |

- 1~3(MS2a)은 서로 선행 관계가 없어 3명이 동시에 시작할 수 있다. IAM만 IAM-01(권한 변경 후 재조사)을 먼저 끝낸다.
- 4~8(MS2b)은 SEA-01(시즌 변수 최소 구현)이 끝난 뒤 시작한다. DB와 배포는 컴퓨팅과 동시에 진행할 수 있다.
- EC2 인스턴스 프로파일은 IAM 그룹이 관리하고 컴퓨팅 그룹은 참조만 한다.

---

## 마일스톤

| 마일스톤 | 기간 | 목표 | 완료 기준 |
| --- | --- | --- | --- |
| MS0 문서·스펙 정리 | ~2026-10-02 [추정] | 문서와 GitHub 실제 상태를 맞추고 착수 전 스펙 결함 제거 | PR #9·#10·#12 머지, wbs.md 오기 정정 반영, CI Terraform 버전 1.11 이상 |
| MS1 state·PR CI·경보 | ~2026-10-18 [추정] | state 저장소와 PR 자동 검사, 안전 게이트 구축. 경보 자원을 신규 생성해 전체 경로 확인 | bootstrap apply 성공, envs/prod 초기화와 잠금 확인, 샘플 PR에 plan 코멘트 자동 게시, RDS 메모리 경보 수신 확인 |
| MS2a 평시 import(위험 낮은 그룹) | ~2026-11-08 [추정] | network·IAM·SSM·storage를 그룹별로 코드 작성·import·plan 확인까지 끝냄 | 그룹별 plan "No changes", 삭제·교체 0건, Import_Log 갱신 |
| MS2b 평시 import(보호 자원 그룹) | 시즌 동결 시작 전(season-up 7일 전) 마감 [확인 필요: 모집 시작일] | EC2·RDS·ALB·CloudFront·CodeDeploy를 같은 방식으로 import하고, 12월 관리자 페이지 오픈에 필요한 CloudFront 설정(CDN-03) 적용 | 그룹별 plan "No changes", EC2-B 재배포 순서 확인, RDS 사전 스냅샷 완료 |
| 동결: 12월 모집 시즌 | season-up 7일 전 ~ season-down 3~7일 후 [추정] | 시즌 전환은 기존 스크립트만 사용, Terraform apply 금지 | 해당 기간 apply 0건 |
| 시즌 직후 검증 | 시즌 종료 후 며칠 [추정] | 평시 상태로 돌아온 뒤 코드와 실제가 다시 같은지 확인 | plan "No changes" 재확인 |
| 2027-01 앱 릴리스 월 | 2027-01 [확인 필요: 배포 주] | DDL 선적용 → 관리자 콘솔 배포 → 출결 기능 배포. Terraform은 자원 추가만 허용 | import·설정 변경 0건 |
| MS3 시즌 전환 코드화·apply 게이트 | ~2027-02 중순 [추정] | 시즌 on/off를 Terraform으로 전환, 승인 후 apply, drift 감지 | 테스트 통과, 승인 없이는 apply 실행 불가, 비시즌 새벽 on→off 리허설 성공 |
| MS4 리허설·이관 완료 | 차기 시즌 4주 전 [추정, 예: 2027-04-30] | 리허설 증적, 문서 완비, 구 스크립트 deprecated | 완료 기준 8항목(→ `docs/overview/migration-plan.md` 7절) 증적, 리허설 2회 성공, backend·frontend 배포 성공 |

- 인원이 1명 이하로 확정되면 MS2b는 동결 뒤로 미루고, 12월 전 목표는 MS2a까지로 줄인다.
- 2027-01 배포 주에는 CodeDeploy·IAM apply 금지.

---

## 마일스톤별 티켓 순서

### MS0 문서·스펙 정리

1. DOC-01 구 WBS PR #12·이슈 #11 종료
2. DOC-02 결정 레지스터 통합
3. DOC-03 이슈 #13 범위 경계 정리 (DOC-02 이후)
4. DOC-04 스펙 결함 일괄 정정 (DOC-02 이후)
5. DOC-05 PR #9·#10 리뷰·머지 (선행 없음, 바로 가능)
6. DOC-06 GitHub Milestone·이슈 생성 (DOC-05 이후)
7. DOC-07 tasks.md에 기준 문서 안내 추가 (선행 없음)

### MS1 state·PR CI·경보

1. STA-01 저장소 디렉터리 구조 (PR #9 머지 후 그룹별 파일만 추가)
2. STA-02 버전·provider 규칙 (STA-01 이후)
3. STA-03 state 버킷 구현 (STA-02 이후, 결정 "state 버킷·키" 필요)
4. STA-04 envs/prod backend 초기화 (STA-03 이후)
5. STA-05 PR CI (STA-02 이후, STA-03·04와 동시 진행 가능)
6. OBS-01 경보 자원 신규 생성 (STA-01 이후, 다른 티켓과 동시 진행 가능)
7. STA-06 property 테스트 실행 환경 (STA-01 이후)
8. STA-07 안전 게이트 + P1·P6 (STA-04·STA-06 이후) — MS2a 모든 그룹의 시작 조건

### MS2a 평시 import(위험 낮은 그룹)

1. NET-01 network 그룹 (STA-07 이후)
2. IAM-01 배포 Role 권한 콘솔 적용 + 재조사 (NET-01과 동시 진행 가능)
3. IAM-02 IAM 롤·정책 그룹 (IAM-01 이후)
4. IAM-03 SSM 파라미터 그룹 (IAM-01 이후, IAM-02와 동시 진행 가능)
5. IAM-04 앱 시크릿 잔여 항목 결정·적용 (IAM-03 이후)
6. STO-01 storage 그룹 (STA-07 이후, NET·IAM과 동시 진행 가능)
7. STO-02 관리 대상 외 버킷 확정 (STO-01과 동시 진행 가능)

### MS2b 평시 import(보호 자원 그룹)

1. SEA-01 시즌 변수 모델 최소 구현 (MS2a 대부분 완료 후)
2. CMP-01 EC2·EIP 그룹 (SEA-01·IAM-02 이후)
3. RDB-01 RDS 그룹 (SEA-01 이후, CMP-01과 동시 진행 가능)
4. CMP-02 Target Group·ALB 그룹 (CMP-01 이후)
5. CDN-01 cdn 모듈 작성 (CMP-02 이후)
6. CDN-02 CloudFront·Route53·ACM import (CDN-01 이후)
7. CDN-03 관리자 CloudFront 보안·SPA 설정 (CDN-02 직후, 동결 시작 전 apply 완료. 12월 관리자 페이지 오픈 조건)
8. DEP-01 deploy 모듈 작성 (IAM-02·STO-01 이후, CMP·RDB·CDN과 동시 진행 가능)
9. DEP-02 CodeDeploy import (DEP-01 이후)
10. CMP-03 EC2-B 재배포 순서 게이트 (CMP-02·DEP-02 이후)
11. STA-08 그룹 간 연결 점검 (CMP·RDB·CDN·DEP 완료 후)
12. STA-09 최종 일치 확인 + P2 (STA-08 이후) — MS2b 완료 조건

### 동결 → 시즌 직후 검증 → 2027-01

1. OPS-01 12월 시즌 동결 시행
2. OPS-02 시즌 종료 후 plan 재확인
3. OPS-03 2027-01 앱 릴리스 월 동결 절차

### MS3 시즌 전환 코드화·apply 게이트

1. SEA-02 시즌 시작(on) 순서 제어 + P4
2. SEA-03 시즌 종료(off) 2단계 apply + P5 (SEA-02 이후)
3. STA-10 배포 workflow 계약 검사 + P8
4. STA-11 승인 후 apply (STA-10 이후, 결정 "apply 승인자" 필요)
5. STA-12 drift 감지 CI + P9 (STA-11 이후)
6. SEA-04 시즌 상태 매핑 테스트 P3
7. OBS-02 접근 로그·대시보드 (권장)
8. STA-13 정적·통합 검증 구성 (SEA-02~STA-12 완료 후)

### MS4 리허설·이관 완료

1. DOC-08 README
2. DOC-09 시즌 전환 런북 (DOC-08과 동시 진행 가능)
3. OPS-04 on 리허설 증적 (STA-13 이후)
4. OPS-05 off 리허설 증적 (OPS-04 이후)
5. OPS-06 backend·frontend 배포 계약 검증
6. OPS-09 런북 인수 테스트 P10 (OPS-04·05 이후)
7. DOC-10 최종 Import_Log
8. DOC-11 workflow·CI 계약 문서
9. DOC-12 결정 결과 문서
10. OPS-10 운영 런북 보강 (권장)
11. OPS-08 구 스크립트 deprecated 안내 (DOC-09 이후)
12. OPS-07 최종 인수 판정 (1~11 완료 후, 마지막 관문)

---

## 전체 티켓 목록

> 노션 데이터베이스로 가져올 때 이 표를 그대로 사용. "12월 전"은 12월 시즌 전 목표 범위 포함 여부.

| 티켓 키 | 티켓 이름 | 명세서 | 규모 | 선행 | 차단 결정 | 마일스톤 | 12월 전 | 상태 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DOC-01 | 구 WBS PR #12·이슈 #11 종료 | DOC | 하루이틀 | 없음 | 없음 | MS0 | 예 | 대기 |
| DOC-02 | 결정 레지스터 통합 | DOC | 하루이틀 | 없음 | 없음 | MS0 | 예 | 대기 |
| DOC-03 | 이슈 #13 범위 경계 정리 | DOC | 하루이틀 | DOC-02 | 없음 | MS0 | 예 | 일부 완료(계획서 문구 반영) |
| DOC-04 | 스펙 결함 일괄 정정 | DOC | 한 주 | DOC-02 | 없음 | MS0 | 예 | 대기 |
| DOC-05 | PR #9·#10 리뷰·머지 | DOC | 하루이틀 | 없음 | 없음 | MS0 | 예 | 리뷰 대기(PR #9·#10) |
| DOC-06 | GitHub Milestone·이슈 생성 | DOC | 하루이틀 | DOC-05 | 없음 | MS0 | 예 | 대기 |
| DOC-07 | tasks.md 기준 문서 안내 | DOC | 하루이틀 | 없음 | 없음 | MS0 | 예 | 대기 |
| DOC-08 | README 작성 | DOC | 한 주 | STA-04, STA-09, STA-12 | 없음 | MS4 | 아니오 | 대기 |
| DOC-09 | 시즌 전환 런북 작성 | DOC | 한 주 | SEA-02, SEA-03 | 없음 | MS4 | 아니오 | 대기 |
| DOC-10 | 최종 Import_Log 갱신 | DOC | 하루이틀 | STA-09, 모든 import 그룹 | 없음 | MS4 | 아니오 | 대기 |
| DOC-11 | workflow·CI 계약 문서 | DOC | 하루이틀 | STA-10 | 없음 | MS4 | 아니오 | 대기 |
| DOC-12 | 결정 결과 문서화 | DOC | 하루이틀 | 관련 결정 전부 | 없음 | MS4 | 아니오 | 대기 |
| STA-01 | 저장소 디렉터리 구조 | STA | 하루이틀 | 없음 | 없음 | MS1 | 예 | 일부 완료(PR #9 리뷰 대기) |
| STA-02 | 버전·provider 규칙 | STA | 하루이틀 | STA-01 | 없음 | MS1 | 예 | 대기 |
| STA-03 | state 버킷 구현 | STA | 한 주 | STA-02 | state 버킷·키 | MS1 | 예 | 대기 |
| STA-04 | envs/prod backend 초기화 | STA | 하루이틀 | STA-03 | state 버킷·키 | MS1 | 예 | 대기 |
| STA-05 | PR CI(fmt·validate·plan) | STA | 한 주 | STA-02 | 브랜치 전략 | MS1 | 예 | 일부 완료(fmt·validate·tflint) |
| STA-06 | property 테스트 실행 환경 | STA | 한 주 | STA-01 | 없음 | MS1 | 예 | 대기 |
| STA-07 | 안전 게이트 + P1·P6 | STA | 2~3주 | STA-04, STA-06 | 없음 | MS1 | 예 | 대기 |
| STA-08 | 그룹 간 연결 점검 | STA | 하루이틀 | CMP-01, RDB-01, CDN-01, DEP-01 | 없음 | MS2b | 예 | 대기 |
| STA-09 | 최종 일치 확인 + P2 | STA | 한 주 | STA-08 | 없음 | MS2b | 예 | 대기 |
| STA-10 | 배포 workflow 계약 검사 + P8 | STA | 하루이틀 | STA-08, DEP-02 | 없음 | MS3 | 아니오 | 대기 |
| STA-11 | 승인 후 apply | STA | 한 주 | STA-10 | apply 승인자 | MS3 | 아니오 | 대기 |
| STA-12 | drift 감지 CI + P9 | STA | 하루이틀 | STA-11 | 없음 | MS3 | 아니오 | 대기 |
| STA-13 | 정적·통합 검증 구성 | STA | 한 주 | SEA-02, SEA-03, STA-12 | 없음 | MS3 | 아니오 | 일부 완료(fmt·validate·tflint) |
| OBS-01 | 경보 자원 신규 생성 | OBS | 한 주 | STA-01 | 없음 | MS1 | 예 | 대기 |
| OBS-02 | 접근 로그·대시보드 | OBS | 하루이틀 | OBS-01, CDN-02 | 없음 | MS3 | 아니오 | 대기 |
| NET-01 | network 그룹 import | NET | 2~3주 | STA-07 | Network ACL 관리 방식 | MS2a | 예 | 대기 |
| IAM-01 | 배포 Role 권한 콘솔 적용 + 재조사 | IAM | 한 주 | STA-07 | 없음 | MS2a | 예 | 대기 |
| IAM-02 | IAM 롤·정책 그룹 import | IAM | 한 주 | IAM-01 | 없음 | MS2a | 예 | 대기 |
| IAM-03 | SSM 파라미터 그룹 import + P7 | IAM | 한 주 | IAM-01 | 앱 시크릿 SecureString 범위 | MS2a | 예 | 대기 |
| IAM-04 | 앱 시크릿 잔여 항목 결정·적용 | IAM | 하루이틀 | IAM-03 | 앱 시크릿 SecureString 범위 | MS2a | 예 | 대기 |
| STO-01 | storage 그룹 import | STO | 한 주 | STA-07 | 관리 대상 버킷·레코드 | MS2a | 예 | 대기 |
| STO-02 | 관리 대상 외 버킷 확정 | STO | 하루이틀 | STO-01 | 관리 대상 버킷·레코드 | MS2a | 예 | 대기 |
| CMP-01 | EC2·EIP 그룹 import | CMP | 2~3주 | SEA-01, IAM-02 | EC2-A EIP 처리, EC2-B 제어 방식 | MS2b | 예 | 대기 |
| CMP-02 | Target Group·ALB 그룹 import | CMP | 한 주 | CMP-01 | 없음 | MS2b | 예 | 대기 |
| CMP-03 | EC2-B 재배포 순서 게이트 | CMP | 하루이틀 | CMP-02, DEP-02 | 없음 | MS2b | 예 | 대기 |
| RDB-01 | RDS 그룹 import | RDB | 한 주 | SEA-01, NET-01 | 없음 | MS2b | 예 | 대기 |
| CDN-01 | cdn 모듈 작성 | CDN | 한 주 | CMP-02 | 없음(admin 포함 여부 해소) | MS2b | 예 | 대기 |
| CDN-02 | CloudFront·Route53·ACM import | CDN | 2~3주 | CDN-01, CMP-02 | WAF WebACL 관리 방식 | MS2b | 예 | 대기 |
| CDN-03 | 관리자 CloudFront 보안·SPA 설정 | CDN | 한 주 | CDN-02 | WAF WebACL 관리 방식 | MS2b | 예 | 대기 |
| DEP-01 | deploy 모듈 작성 | DEP | 하루이틀 | IAM-02, STO-01 | CodeDeploy 태그 방식(거의 해소) | MS2b | 예 | 대기 |
| DEP-02 | CodeDeploy import | DEP | 한 주 | DEP-01 | CodeDeploy 태그 방식(거의 해소) | MS2b | 예 | 대기 |
| SEA-01 | 시즌 변수 모델 최소 구현 | SEA | 한 주 | STA-07, MS2a | 없음 | MS2b | 예 | 대기 |
| SEA-02 | 시즌 시작(on) 순서 제어 + P4 | SEA | 한 주 | CMP-02, CDN-02, STA-09 | 없음 | MS3 | 아니오 | 대기 |
| SEA-03 | 시즌 종료(off) 2단계 apply + P5 | SEA | 한 주 | SEA-02 | 없음 | MS3 | 아니오 | 대기 |
| SEA-04 | 시즌 상태 매핑 테스트 P3 | SEA | 하루이틀 | SEA-01 | 없음 | MS3 | 아니오 | 대기 |
| OPS-01 | 12월 시즌 동결 시행 | OPS | 하루이틀 | STA-09 | 없음 | 동결 | 아니오 | 대기 |
| OPS-02 | 시즌 종료 후 plan 재확인 | OPS | 하루이틀 | OPS-01 | 없음 | 시즌 직후 검증 | 아니오 | 대기 |
| OPS-03 | 2027-01 앱 릴리스 월 동결 절차 | OPS | 한 주 | OPS-02 | 없음 | 2027-01 | 아니오 | 대기 |
| OPS-04 | on 리허설 증적 | OPS | 한 주 | STA-13, SEA-02 | 없음 | MS4 | 아니오 | 대기 |
| OPS-05 | off 2단계 리허설 증적 | OPS | 한 주 | OPS-04, SEA-03 | 없음 | MS4 | 아니오 | 대기 |
| OPS-06 | backend·frontend 배포 계약 검증 | OPS | 하루이틀 | STA-10 | 없음 | MS4 | 아니오 | 대기 |
| OPS-07 | 최종 인수 판정 | OPS | 한 주 | OPS-04~06, OPS-08, OPS-09, DOC-08~12 | 없음 | MS4 | 아니오 | 대기 |
| OPS-08 | 구 스크립트 deprecated 안내 | OPS | 하루이틀 | DOC-09 | 없음 | MS4 | 아니오 | 대기 |
| OPS-09 | 런북 인수 테스트 P10 | OPS | 한 주 | OPS-04, OPS-05 | 없음 | MS4 | 아니오 | 대기 |
| OPS-10 | 운영 런북 보강 | OPS | 한 주 | DOC-09 | 없음 | MS4 | 아니오 | 대기 |

---

## 결정 대기 항목

> 기한이 지나면 기본안을 채택한다. 결정 주체는 모두 [추정].

| 결정 | 기본안 | 결정 주체 | 기한 | 막는 티켓 | 상태 |
| --- | --- | --- | --- | --- | --- |
| state 버킷·키 | 전용 신규 버킷, 키 `envs/prod/terraform.tfstate` | 인프라 담당 | 2026-10-02 | STA-03, STA-04 | 대기 |
| EC2-A EIP 처리 | 기존 EIP와 연결을 import, prevent_destroy | 인프라 담당 | 2026-10-02 | CMP-01 | 사실상 해소 |
| EC2-B 제어 방식 | `aws_ec2_instance_state` 사용, ASG 전환 안 함 | 인프라 담당 + 백엔드 리드 | 2026-10-02 | CMP-01 | 대기 |
| admin CloudFront import 포함 | 기존 자원 import에 포함 | 인프라 담당 | 즉시 | CDN-01 | 해소 |
| CodeDeploy 태그 방식 | 현행 태그 방식 유지 | 백엔드 리드 | 2026-11-06 | DEP-01, DEP-02 | 거의 해소 |
| 앱 시크릿 SecureString 범위 | 잔여 항목은 현행 유지, 후속 이슈로 분리 | 백엔드 리드 | 2026-10-16 | IAM-03, IAM-04 | 일부 해소 |
| 관리 대상 버킷·레코드 | 서비스 버킷만 관리, 나머지는 제외 사유 기록 | 운영진 + 인프라 담당 | 2026-10-09 | STO-01, STO-02 | 대기 |
| WAF WebACL 관리 방식 | CloudFront에서 기존 WebACL을 참조만 함, WebACL 자체 import는 보류 | 인프라 담당 | 2026-10-16 | CDN-02, CDN-03 | 신규 |
| 브랜치 전략 | 조직 표준(dev → main) | 인프라 담당 + 운영진 | 2026-10-16 | STA-05 | 신규 |
| Network ACL 관리 방식 | 현행 그대로 import | 인프라 담당 | 2026-10-09 | NET-01 | 대기 |
| CloudTrail 존재 여부 | 조사 후 결정 | 인프라 담당 | 2026-10-09 | 없음(감사 수단) | 신규 |
| apply 승인자 | 2명 이상 | 운영진 | 2027-01-31 | STA-11 | 대기 |

---

## 부록 A. tasks.md 번호 ↔ 티켓 키

| tasks.md | 티켓 키 | 비고 |
| --- | --- | --- |
| 1.1, 1.3 | (완료, PR #10 리뷰 대기) | 이후 그룹별 재조사·기록은 각 그룹 티켓의 기능으로 포함 |
| 1.2 | DOC-02 | |
| 2.1 | STA-01 | PR #9 |
| 2.2 | STA-02 | Terraform 버전 1.9 → 1.11 이상 |
| 3.1 / 3.2 | STA-03 / STA-04 | |
| 4.1 + 6.1 | NET-01 | 모듈 작성과 import를 한 티켓으로 합침 |
| 4.2 + 6.2(IAM) | IAM-02 | 같은 방식 |
| 4.3 + 6.2(SSM) + 8.4 | IAM-03 | 같은 방식 |
| 4.4 + 6.3 | STO-01 | 같은 방식 |
| 4.5 + 6.4 | CMP-01 | 같은 방식 |
| 4.6 + 6.5 | RDB-01 | 같은 방식 |
| 4.7 / 6.7 | CDN-01 / CDN-02 | 한 PR로 하기엔 커서 두 티켓 유지 |
| 4.8 / 6.8 | DEP-01 / DEP-02 | |
| 5.1 / 5.2 | SEA-01 / STA-08 | |
| 5.3 + 8.1 + 8.3 | STA-07 | import 시작 전으로 앞당김 |
| 6.6 / 6.9 + 8.6 | CMP-02 / STA-09 | |
| 7.1 + 8.7 / 7.2 + 8.8 | SEA-02 / SEA-03 | |
| 7.3 + 8.5 | STA-10 | |
| 7.4 | STA-05 | MS1로 앞당김 |
| 7.5 / 7.6 + 8.9 | STA-11 / STA-12 | |
| 8.2 | SEA-04 | |
| 8.10 | OPS-09 | |
| 8.11 | STA-13 | |
| 9.1~9.5 | DOC-08~DOC-12 | |
| 9.6 | OPS-08 | |
| 10.1 + 10.5 | OPS-07 | 최종 판정 하나로 합침 |
| 10.2 / 10.3 / 10.4 | OPS-04 / OPS-05 / OPS-06 | |
| 11, 12 (체크포인트) | 별도 티켓 없음 | STA-07, STA-09, OPS-07의 완료 확인 방법에 포함 |

- tasks.md에 없는 신규 티켓: DOC-01·03·05·06·07, STA-06, OBS-01·02, IAM-01·04, STO-02, CMP-03, CDN-03, OPS-01·02·03·10.

## 부록 B. 이슈 #13 항목별 반영 현황

| 항목 | 반영 위치 | 비고 |
| --- | --- | --- |
| R1 관리자 콘솔 배포 워크플로우 | 제외(IAM-01만 포함) | frontend_admin 저장소 작업. 배포 Role 권한만 이 WBS |
| R2 배포 Role 권한 | IAM-01 | IAM import 전에 콘솔 적용 후 재조사 |
| R3 백엔드 배포 방식 변수화 | 제외, 충돌 방지만(STA-10, DEP-02) | backend 저장소 작업. 계약 검사는 이름·ARN만 |
| R4 DDL 선적용 런북 | OPS-03 일부 | RDS 유지보수 시간·스냅샷만 인프라 범위 |
| R5 인프라 보안 보완 | CDN-03-04 | 세부 내용은 팀 비공개 문서 |
| R6 로그 중앙화·최소 경보 | OBS-01 | 시즌 ALB 경보는 12월에 수동 생성 또는 생략 |
| R8 운영 런북 | OPS-10 | |
| 백엔드 연계(관리자 인가·감사 로그) | 제외 | backend 저장소 별도 이슈 |
| R9 WAF 규칙 보완 | CDN-03-01 | WebACL 자체는 참조만(결정 "WAF WebACL 관리 방식") |
| R10 관리자 SPA·보안 헤더 | CDN-03-02, CDN-03-03 | |
| R11 CodeDeploy·ALB 연동 | 보류 | 평시엔 ALB가 없어 검증 불가. MS3 이후 검토 |
| R12 관리자 콘솔 dev 환경 | 제외 | frontend_admin 저장소 결정 사항 |
| R15 접근 로그·대시보드 | OBS-02 | |
| R18 스펙 변경 수동 승인 | DOC-12 | RDS 메모리 경보 초과 시 DB 클래스 상향도 이 절차 |
| 기존 admin 자원 import | CDN-01·02, `overview/migration-plan.md` 비목표 문구 | |
| infra-spec.md 최신화(EIP·WAF) | DOC-04-09 | |
| 시즌 변수에 `ignore_changes` 금지 | CMP-01-03 | 기능 태그·인스턴스 상태는 무시 목록에 넣지 않음 |
| 보류 항목(API Gateway, 서브넷 분리, 스펙 상향, IP 허용 목록, 2FA, Flyway 등) | 제외 | #13에서 보류로 결정 |

## 확인 필요 사항

| 질문 | 확인 주체 | 필요 시점 |
| --- | --- | --- |
| 12월 모집 시즌 시작·종료일 | 운영진 | 2026-09-30 |
| 2027-01 출결 기능 배포 주 | 운영진 + 백엔드 리드 | 2026-09-30 |
| 참여 인원·주당 투입 시간 | 인프라 담당 + 운영진 | 2026-09-30 |
| 티켓별 담당자 | 인프라 담당 | 2026-10-02 |
| property 테스트 범위: 설계대로 유지 vs plan 검사 스크립트로 축소 | 인프라 담당 + PM | 2026-10-09 |
| dev 프론트 배포 워크플로 최근 실행 성공 여부 | 인프라 담당 | 2026-10-09 |
| Terraform 실행 자격 증명 종류(장기 액세스 키 여부) | 인프라 담당 | 2026-10-09 |
