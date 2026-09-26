# Phase 일정

| 기준일 | 근거 | 성격 |
| --- | --- | --- |
| 2026-09-26 | `docs/wbs/00-wbs.md`(WBS), `docs/records/decisions.md`(결정·확인 필요 레지스터) | Phase별 일정과 티켓 순서. 날짜는 팀 확인 전까지 기준선, 담당자는 노션에서 배정 |

> 팀원에게 일을 나눌 때 보는 페이지. 티켓 상세는 각 명세서(`docs/wbs/1x~5x-*.md`), 티켓 전체 목록은 WBS 참조

---

## Phase별 일정

> 팀원에게는 Phase 단위로 일을 나눔. Phase 번호는 이전 계획서(Phase 0~5)를 따르되 3·4 순서만 바꿈
> 이전 계획서와 달라진 점: ① PR 검사·안전 게이트는 팀원 PR을 받기 전에 필요해 Phase 2 준비로 앞당김 ② Phase 3·4 순서를 바꿈. 시즌 전환을 운영 환경에 apply하려면 승인 후 apply가 먼저 있어야 하므로 Phase 3 = 인프라 CI/CD, Phase 4 = 시즌 전환 코드화 ③ 시즌 변수 최소 구현(SEA-01)은 Phase 2 2차로, 구 스크립트 정리(OPS-08)는 Phase 5로 옮김

| Phase | 기간 | 담당 | 목표 | 티켓 | 완료 기준 |
| --- | --- | --- | --- | --- | --- |
| Phase 0 사전 조사 | 완료(2026-09-26) | 인프라 리드 | 운영 자원 조사, 결정 항목 정리 | 없음(PR #10) | 조사 기록 3종 머지 |
| Phase 1 저장소·state 기반 | ~2026-10-18 [추정] | 인프라 리드 | 문서 정리, 저장소 구조, state 저장소 | DOC-01~07, STA-01~04 | PR #9·#10·#12 머지, CI Terraform 1.11 이상, bootstrap apply 성공, envs/prod 초기화와 잠금 확인 |
| Phase 2 준비 | ~2026-10-25 [추정] | 노션에서 배정 | 팀원 PR을 받기 전 PR 검사·안전 게이트·경보 구축 | STA-05, STA-06, STA-07, OBS-01 | 샘플 PR에 plan 코멘트 자동 게시, 교체·삭제 plan 차단 확인, RDS 메모리 경보 수신 |
| Phase 2 1차 (위험 낮은 그룹) | ~2026-11-08 [추정] | 팀원(그룹별) | 네트워크·IAM·SSM·스토리지 import | NET-01, IAM-01~04, STO-01~02 | 그룹별 plan "No changes", 삭제·교체 0건, import 기록 갱신 |
| Phase 2 2차 (보호 자원 그룹) | season-up 7일 전 [확인 필요: 모집 시작일] | 팀원(그룹별) | 시즌 변수 최소 구현, 서버·DB·CDN·배포 import, 관리자 CloudFront 설정 | SEA-01, CMP-01~03, RDB-01, CDN-01~03, DEP-01~02 | 그룹별 plan "No changes", EC2-B 재배포 순서 확인, RDS 사전 스냅샷, 관리자 페이지 접속 확인 |
| Phase 2 마무리 | Phase 2 2차와 같음 | 노션에서 배정 | 그룹 간 연결 점검, 전체 일치 확인 | STA-08, STA-09 | 전체 plan "No changes" |
| 운영 구간 | 12월 시즌 ~ 2027-01 | 인프라 리드 | 12월 동결, 시즌 직후 검증, 2027-01 앱 릴리스 월 | OPS-01, OPS-02, OPS-03 | 동결 기간 apply 0건, 시즌 후 plan "No changes" 재확인, 2027-01 import·설정 변경 0건 |
| Phase 3 인프라 CI/CD | ~2027-02 중순 [추정] | 노션에서 배정 | 배포 계약 검사, 승인 후 apply, drift 감지 | STA-10~12, OBS-02 | 승인 없이 apply 불가, 일일 drift 감지 동작, 배포 계약 불일치 0건 |
| Phase 4 시즌 전환 코드화 | ~2027-03 말 [추정] | 노션에서 배정 | 시즌 on/off를 Terraform으로 전환(승인 후 apply 사용), 정적·통합 검증 구성 | SEA-02~04, STA-13 | 테스트 통과, 비시즌 새벽 on→off 리허설 성공 |
| Phase 5 리허설·이관 완료 | 차기 시즌 4주 전 [추정, 예: 2027-04-30] | 노션에서 배정 | 리허설 증적, 문서 완비, 구 스크립트 deprecated | DOC-08~12, OPS-04~10 | 완료 기준 8항목(→ `docs/overview/migration-plan.md` 8절) 증적, 리허설 2회 성공 |

- 12월 전 목표는 Phase 2 완료. 인원이 1명 이하로 확정되면 Phase 2 2차·마무리를 동결 뒤로 미루고 12월 전 목표를 Phase 2 1차까지로 줄임
- 2027-01 배포 주에는 CodeDeploy·IAM apply 금지

---

## Phase별 티켓 순서

### Phase 1 저장소·state 기반 (인프라 리드)

1. DOC-05 PR #9·#10 리뷰·머지 (선행 없음)
2. DOC-01 새 WBS PR #12 머지 (DOC-05 이후)
3. DOC-02 결정 레지스터 통합
4. DOC-03 이슈 #13 범위 경계 정리 (DOC-02 이후)
5. DOC-04 스펙 결함 일괄 정정 (DOC-02 이후)
6. DOC-06 GitHub Milestone·이슈 생성 (DOC-05 이후)
7. DOC-07 tasks.md에 기준 문서 안내 추가 (선행 없음)
8. STA-01 저장소 디렉터리 구조 (PR #9 머지 후 그룹별 파일만 추가)
9. STA-02 버전·provider 규칙 (STA-01 이후)
10. STA-03 state 버킷 구현 (STA-02 이후, 결정 "state 버킷·키" 필요)
11. STA-04 envs/prod backend 초기화 (STA-03 이후)

### Phase 2 준비 (팀원 PR을 받기 전)

1. STA-05 PR CI (STA-02 이후, Phase 1과 동시 진행 가능)
2. OBS-01 경보 자원 신규 생성 (STA-01 이후)
3. STA-06 property 테스트 실행 환경 (STA-01 이후)
4. STA-07 안전 게이트 + P1·P6 (STA-04·STA-06 이후) — Phase 2 1차 모든 그룹의 시작 조건

### Phase 2 1차 (위험 낮은 그룹, 팀원)

1. NET-01 network 그룹 (STA-07 이후)
2. IAM-01 배포 Role 권한 콘솔 적용 + 재조사 (NET-01과 동시 진행 가능)
3. IAM-02 IAM 롤·정책 그룹 (IAM-01 이후)
4. IAM-03 SSM 파라미터 그룹 (IAM-01 이후, IAM-02와 동시 진행 가능)
5. IAM-04 앱 시크릿 잔여 항목 결정·적용 (IAM-03 이후)
6. STO-01 storage 그룹 (STA-07 이후, NET·IAM과 동시 진행 가능)
7. STO-02 관리 대상 외 버킷 확정 (STO-01 이후)

### Phase 2 2차 (보호 자원 그룹, 팀원)

1. SEA-01 시즌 변수 모델 최소 구현 (Phase 2 1차 대부분 완료 후)
2. CMP-01 EC2·EIP 그룹 (SEA-01·IAM-02 이후)
3. RDB-01 RDS 그룹 (SEA-01·NET-01 이후, CMP-01과 동시 진행 가능)
4. CMP-02 Target Group·ALB 그룹 (CMP-01 이후)
5. CDN-01 cdn 모듈 작성 (CMP-02 이후)
6. CDN-02 CloudFront·Route53·ACM import (CDN-01 이후)
7. CDN-03 관리자 CloudFront 보안·SPA 설정 (CDN-02 직후, 동결 시작 전 apply 완료. 12월 관리자 페이지 오픈 조건)
8. DEP-01 deploy 모듈 작성 (IAM-02·STO-01 이후, CMP·RDB·CDN과 동시 진행 가능)
9. DEP-02 CodeDeploy import (DEP-01 이후)
10. CMP-03 EC2-B 재배포 순서 게이트 (CMP-02·DEP-02 이후)

### Phase 2 마무리

1. STA-08 그룹 간 연결 점검 (Phase 2 2차 완료 후)
2. STA-09 최종 일치 확인 + P2 (STA-08 이후) — Phase 2 완료 조건

### 운영 구간 (12월 시즌 ~ 2027-01)

1. OPS-01 12월 시즌 동결 시행
2. OPS-02 시즌 종료 후 plan 재확인
3. OPS-03 2027-01 앱 릴리스 월 동결 절차

### Phase 3 인프라 CI/CD

1. STA-10 배포 workflow 계약 검사 + P8
2. STA-11 승인 후 apply (STA-10 이후, 결정 "apply 승인자" 필요)
3. STA-12 drift 감지 CI + P9 (STA-11 이후)
4. OBS-02 접근 로그·대시보드 (권장, 동시 진행 가능)

### Phase 4 시즌 전환 코드화 (Phase 3 이후)

1. SEA-02 시즌 시작(on) 순서 제어 + P4 (STA-11 이후)
2. SEA-03 시즌 종료(off) 2단계 apply + P5 (SEA-02 이후)
3. SEA-04 시즌 상태 매핑 테스트 P3
4. STA-13 정적·통합 검증 구성 (SEA-02·SEA-03·STA-12 완료 후)

### Phase 5 리허설·이관 완료

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
