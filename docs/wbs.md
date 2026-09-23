# Terraform 마이그레이션 WBS 및 Epic-Ticket 산정

BOAZ 운영 AWS 인프라 Terraform 마이그레이션의 작업 분해 구조(WBS)와 GitHub 이슈 산정 문서.

- 근거: `.kiro/specs/product-infra-migration/{requirements.md,design.md,tasks.md}`
- GitHub 운영: Epic·Task 모두 이슈로 관리. 최상위 묶음은 마일스톤 또는 라벨(`terraform-migration`)로 표현.
- 작업량 표기: T-shirt 사이즈 (S / M / L / XL)
- 상태: Epic 1은 진행 중(PR #9, #10), 나머지는 대기

## Epic 목록

| Epic | 제목 | 관련 요구사항 | tasks.md 매핑 | 작업량 | 상태 |
|---|---|---|---|---|---|
| E1 | 사전 준비: 조사 인벤토리 및 저장소 뼈대 | R1, R2(일부), R3(문서), R13 | 1.1, 1.2, 1.3, 2.1 | M | 진행 중 |
| E2 | 상태 저장소 구성 (bootstrap state) | R1(버전), R2 | 2.2, 3.1, 3.2 | M | 대기 |
| E3 | 재사용 모듈 8종 구현 | R4~R9, R11 | 4.1~4.8 | XL | 대기 |
| E4 | 운영 환경 조립 및 안전 게이트 (envs/prod) | R1, R5, R6, R10, R12 | 5.1, 5.2, 5.3 | L | 대기 |
| E5 | 단계별 자원 코드 편입 (import 8그룹) | R3, R4~R9 | 6.1~6.9 | XL | 대기 |
| E6 | 시즌 전환 안전장치 및 CI/CD | R8, R10, R12 | 7.1~7.6 | L | 대기 |
| E7 | 검증 (property/통합/정적 테스트) | P1~P10 전체 | 8.1~8.11 | L | 대기 |
| E8 | 운영 문서 및 구 스크립트 정리 | R8, R9, R10, R13 | 9.1~9.6, 10.1~10.5 | M | 대기 |

작업량 기준: S(반나절), M(1~2일), L(3~5일), XL(1주+). 실제 배정 시 담당·기한과 함께 조정.

---

## E1. 사전 준비: 조사 인벤토리 및 저장소 뼈대

목표: 조사로 실제 식별자 확정, 저장소 폴더 구조 확보. 이후 모든 작업의 전제.
관련 요구사항: R1.1~1.3, R2.1, R3.1·3.4~3.6, R13.4
진입 조건: 없음 (시작점)
완료 조건: 조사 문서 3종 + 저장소 뼈대 머지

| Task | 제목 | tasks.md | 작업량 | 상태 | GitHub |
|---|---|---|---|---|---|
| E1-T1 | 저장소 폴더 구조 생성 | 2.1 | S | 완료 | 이슈 #7 / PR #9 |
| E1-T2 | AWS 조사 인벤토리 작성 (inventory.md) | 1.1 | M | 완료 | 이슈 #8 / PR #10 |
| E1-T3 | 결정 필요 항목 정의 (decisions.md) | 1.2 | S | 완료 | 이슈 #8 / PR #10 |
| E1-T4 | Import 기록 양식 작성 (import-log.md) | 1.3 | S | 완료 | 이슈 #8 / PR #10 |

---

## E2. 상태 저장소 구성 (bootstrap state)

목표: Terraform state를 저장할 S3 버킷과 잠금(native lock) 기반 구성. 이후 모든 코드 작업의 토대.
관련 요구사항: R1.4·1.6·1.7, R2.1~2.7
진입 조건: E1 완료, decisions.md의 state 버킷·키 확정
완료 조건: bootstrap apply로 state 버킷 생성, envs/prod backend 초기화 성공

| Task | 제목 | tasks.md | 작업량 | 상태 |
|---|---|---|---|---|
| E2-T1 | Terraform/provider 버전·alias·lockfile 규칙 정의 | 2.2 | S | 대기 |
| E2-T2 | bootstrap S3 state 버킷·보호 정책 구현 | 3.1 | M | 대기 |
| E2-T3 | envs/prod backend 및 초기화 절차 구현 | 3.2 | M | 대기 |

선행 결정: state 버킷·키 (decisions.md). 미확정 시 E2 착수 불가.

---

## E3. 재사용 모듈 8종 구현

목표: network/compute/database/storage/cdn/deploy/iam/params 모듈을 import 가능한 형태로 구현.
관련 요구사항: R4(network), R5(compute), R6(database), R7(storage/cdn), R8(deploy/iam), R9(params), R11(태그)
진입 조건: E2 완료
완료 조건: 8개 모듈 코드 완성, 단독 validate 통과

| Task | 제목 | tasks.md | 작업량 | 상태 | 선행 결정 |
|---|---|---|---|---|---|
| E3-T1 | modules/network 구현 | 4.1 | M | 대기 | - |
| E3-T2 | modules/iam 구현 | 4.2 | M | 대기 | - |
| E3-T3 | modules/params 구현 | 4.3 | M | 대기 | SecureString 전환 |
| E3-T4 | modules/storage 구현 | 4.4 | M | 대기 | 관리 대상 버킷 확정 |
| E3-T5 | modules/compute 구현 | 4.5 | L | 대기 | EIP, EC2-B 제어 방식 |
| E3-T6 | modules/database 구현 | 4.6 | M | 대기 | - |
| E3-T7 | modules/cdn 구현 | 4.7 | L | 대기 | admin 배포 포함 여부 |
| E3-T8 | modules/deploy 구현 | 4.8 | M | 대기 | CodeDeploy 태그 타겟 방식 |

병렬성: T1~T4는 병렬 가능. T5(compute)는 T2(iam) 이후. T6(database)는 T1(network) 이후. T7(cdn)은 T5 이후. T8(deploy)은 T2·T4 이후.

---

## E4. 운영 환경 조립 및 안전 게이트 (envs/prod)

목표: 8개 모듈을 envs/prod에서 연결, season_mode 모델·안전 게이트 구현.
관련 요구사항: R1.2~1.4, R5, R6, R10.1~10.4, R12.6~12.7
진입 조건: E3 완료
완료 조건: envs/prod validate 통과, 안전 게이트 동작

| Task | 제목 | tasks.md | 작업량 | 상태 |
|---|---|---|---|---|
| E4-T1 | season_mode 입력·canonical locals·변수 모델 구현 | 5.1 | M | 대기 |
| E4-T2 | 모듈 wiring·dependency·workflow 계약 output 연결 | 5.2 | M | 대기 |
| E4-T3 | destroy/replace·secret·identifier 안전 게이트 구현 | 5.3 | L | 대기 |

---

## E5. 단계별 자원 코드 편입 (import 8그룹)

목표: 조사 확정 식별자로 운영 자원을 그룹별 선언적 import, No changes 수렴.
관련 요구사항: R3 전체, R4~R9
진입 조건: E4 완료, 각 그룹 관련 결정 완료
완료 조건: 최종 plan No changes, Import_Log 갱신, 보호 자원 무교체 확인

| Task | 제목 | tasks.md | 작업량 | 상태 |
|---|---|---|---|---|
| E5-T1 | network 그룹 import·수렴 plan | 6.1 | M | 대기 |
| E5-T2 | IAM·SSM 파라미터 그룹 import | 6.2 | M | 대기 |
| E5-T3 | S3 storage 그룹 import | 6.3 | M | 대기 |
| E5-T4 | EC2 compute 그룹 import·drift 보호 | 6.4 | L | 대기 |
| E5-T5 | RDS database 그룹 import·데이터 보호 게이트 | 6.5 | M | 대기 |
| E5-T6 | Target Group·ALB 그룹 import | 6.6 | M | 대기 |
| E5-T7 | CloudFront·Route53·ACM 그룹 import·origin 보호 | 6.7 | L | 대기 |
| E5-T8 | CodeDeploy 그룹 import·설정 보존 | 6.8 | M | 대기 |
| E5-T9 | 단계별 No changes·게이트·최종 수렴 절차 | 6.9 | M | 대기 |

순차성 강함: import는 tasks.md 표준 순서(network→iam/params→storage→compute→database→alb→cdn→deploy)를 따름. 각 단계 plan 통과 후 다음 진행.

---

## E6. 시즌 전환 안전장치 및 CI/CD

목표: 시즌 시작/종료 게이트, PR/apply/drift CI 파이프라인 구현.
관련 요구사항: R8.3~8.7, R10.5~10.8, R12.1~12.5
진입 조건: E5 완료
완료 조건: 시즌 게이트 동작, CI 3종(PR/apply/drift) 동작

| Task | 제목 | tasks.md | 작업량 | 상태 | 선행 결정 |
|---|---|---|---|---|---|
| E6-T1 | 시즌 시작 on dependency·900초 health 게이트 | 7.1 | M | 대기 | - |
| E6-T2 | 시즌 종료 off 2단계 apply 게이트 | 7.2 | M | 대기 | - |
| E6-T3 | workflow output 계약 검사 | 7.3 | S | 대기 | - |
| E6-T4 | PR용 Infrastructure CI | 7.4 | M | 대기 | 브랜치 전략 |
| E6-T5 | main apply·protected Environment 승인 게이트 | 7.5 | M | 대기 | apply 승인자 |
| E6-T6 | 예약 drift 감지 CI | 7.6 | S | 대기 | - |

---

## E7. 검증 (property/통합/정적 테스트)

목표: correctness properties P1~P10을 자동화 테스트로 검증.
관련 요구사항: P1~P10 (R3, R5, R6, R8~R13 연동)
진입 조건: 대상 기능 구현 완료 (E4~E6과 병행 가능)
완료 조건: 10개 property 테스트 + 정적/통합 검증 통과

| Task | 제목 | tasks.md | property | 작업량 | 상태 |
|---|---|---|---|---|---|
| E7-T1 | 보호 자원 action gate PBT | 8.1 | P1 | S | 대기 |
| E7-T2 | season_mode canonical 모델 PBT | 8.2 | P3 | S | 대기 |
| E7-T3 | secret redaction PBT | 8.3 | P6 | S | 대기 |
| E7-T4 | Infra Parameter 12개·파생 PBT | 8.4 | P7 | S | 대기 |
| E7-T5 | workflow output 계약 equality PBT | 8.5 | P8 | S | 대기 |
| E7-T6 | import 수렴·No changes 정적 검사 | 8.6 | P2 | M | 대기 |
| E7-T7 | 시즌 시작 dependency·health 통합 테스트 | 8.7 | P4 | M | 대기 |
| E7-T8 | 시즌 종료 2단계 안전 순서 통합 테스트 | 8.8 | P5 | M | 대기 |
| E7-T9 | OIDC·CI 안전 정적 검사 | 8.9 | P9 | S | 대기 |
| E7-T10 | runbook 인수 evidence 통합 테스트 | 8.10 | P10 | M | 대기 |
| E7-T11 | Terraform 정적·대표 통합 검증 실행 구성 | 8.11 | P1~P10 | M | 대기 |

---

## E8. 운영 문서 및 구 스크립트 정리

목표: 한국어 README·런북·문서 완성, 구 스크립트 deprecated 처리, DoD 검증.
관련 요구사항: R8.7, R9.5~9.6, R10.10, R13 전체
진입 조건: E5~E7 대부분 완료
완료 조건: 문서 완비, 구 스크립트 4종 deprecated, DoD 전체 충족

| Task | 제목 | tasks.md | 작업량 | 상태 |
|---|---|---|---|---|
| E8-T1 | 한국어 README 작성 | 9.1 | S | 대기 |
| E8-T2 | 한국어 시즌 전환 runbook 작성 | 9.2 | M | 대기 |
| E8-T3 | 최종 Import_Log·증적 갱신 | 9.3 | S | 대기 |
| E8-T4 | workflow contract·CI 운영 계약 문서 | 9.4 | S | 대기 |
| E8-T5 | 결정 항목·승인 결과 문서화 | 9.5 | S | 대기 |
| E8-T6 | 구 스크립트 이관·deprecated 안내 (backend 레포 문서) | 9.6 | S | 대기 |
| E8-T7 | 최종 acceptance harness·DoD 검증 | 10.1~10.5 | M | 대기 |

---

## 결정 필요 항목이 차단하는 Epic (decisions.md 연동)

| 결정 항목 | 상태 | 차단 Epic/Task |
|---|---|---|
| state 버킷·키 | 결정 대기 | E2 전체 |
| EC2-A Elastic IP | 결정 대기 | E3-T5, E5-T4 |
| EC2-B 제어 방식 | 결정 대기 | E3-T5, E5-T4 |
| 앱 secret SecureString 전환 | 결정 대기 | E3-T3, E5-T2 |
| apply 승인자 | 결정 대기 | E6-T5 |
| 브랜치 전략 | 결정 대기 | E6-T4 |
| admin 배포 포함 여부 | 결정 대기 | E3-T7, E5-T7 |
| CodeDeploy 태그 타겟 방식 | 결정 대기 | E3-T8, E5-T8 |
| 관리 대상 버킷·레코드 확정 | 결정 대기 | E3-T4, E5-T3 |

---

## Epic 진행 순서 (요약)

```text
E1 (진행 중)
 └→ E2
     └→ E3 ─┬→ E4 ─→ E5 ─→ E6 ─→ E8
            └────────→ E7 (E4~E6과 병행)
```

E1 완료(PR #9·#10 머지) 후 결정 필요 항목을 확정해야 E2 이후로 진입 가능.
