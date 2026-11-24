# OBS 모니터링·경보 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- 기존 계획에 없던 모니터링·경보를 새 자원으로 만듦
- 기존 자원을 건드리지 않고 새로 만들기만 하므로, state·backend·CI가 제대로 동작하는지 운영 자원 import 전에 확인하는 첫 작업으로 씀
- RDS 여유 메모리 부족(최저 약 25MB 실측)을 가장 먼저 감시함

**범위:** CloudWatch Agent, SNS 이메일 경보, 로그 그룹 보관 기간, CloudFront 접근 로그, 대시보드
**범위 밖:** 시즌 ALB 경보 자동화(12월은 수동 생성 또는 생략)

---

## OBS-01 경보 자원 신규 생성

**목적:** 모니터링·경보 자원을 Terraform으로 관리함. 콘솔로 이미 만든 자원은 import하고, 없는 경보만 새로 만듦

> 2026-11-15 재조사 결과: 앱 로그 그룹(보관 30일), SNS 주제 `boaz-alerts`와 이메일 구독, EC2·RDS 경보 12개, CloudWatch Agent(네임스페이스 `BOAZ/Backend`, 메모리·디스크 지표)가 2026-05~06에 콘솔로 이미 만들어져 있었음. 같은 자원을 새로 만들면 로그 그룹 생성이 실패하고 알림이 중복되므로 현행 값 그대로 import함(#95). 새로 만든 자원은 CloudFront api 5xx 경보와 그 SNS 주제·구독(us-east-1)뿐임. 현황은 `docs/records/inventory.md` 14절

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-01 | 없음 | Phase 2 1차 | 신규 | #13(R6) |

> 그룹 값 키·테스트: 경보 수신 이메일은 1-1-1절 표의 `alert_emails` 키를 따름. 이 키를 쓰는 PR에서 `envs/prod/tests/season.tftest.hcl`의 obs 가짜 값을 같은 PR에서 추가함. import 블록이 없어 `override_resource`는 필요 없음(1-2절)

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| OBS-01-01 | EC2에 CloudWatch Agent 설치·설정(기존 IAM 롤 권한 사용) | `aws cloudwatch list-metrics`에 사용자 지정 지표 조회됨 |
| OBS-01-02 | RDS FreeableMemory 경보 생성 | 임계값을 낮춰 테스트 알림 수신 |
| OBS-01-03 | 앱 로그 30일 보관, EC2 메모리·디스크 지표 수집. Agent 켜기 전에 로그 그룹을 먼저 만듦(자동 생성 시 무기한 보관) | 로그 그룹 보관 기간 30일 |
| OBS-01-04 | 헬스체크·5xx 비율·EC2 상태 검사·RDS 저장 공간·CPU 경보 추가 | SNS 구독 이메일로 각 경보 테스트 수신. 알림 경로(SNS 주제)마다 대표 경보 1개를 `set-alarm-state`로 울려 확인함: 서울 `boaz-alerts`는 RDS 여유 메모리 경보, us-east-1은 CloudFront 5xx 경보(2026-11-15 확인) |
| OBS-01-05 | 기존 운영 자원은 변경하지 않음. 콘솔로 만든 모니터링 자원은 import만 하고, 그 밖에는 새로 만들기만 함 | plan에 기존 자원 변경 없음, import와 생성만 존재 |
| OBS-01-06 | Discord 알림 Lambda(SNS→Lambda→웹훅). 코드는 저장소 소스를 `archive_file`로 zip하고 버킷은 쓰지 않음. 웹훅 URL은 수동 등록한 SSM SecureString을 실행 시 읽음(Terraform 관리 제외). 실행 역할의 복호화 권한 확인. Discord 응답이 2xx가 아니면(429 포함) Lambda가 예외를 던지고, Lambda의 실패 시 대상(on-failure destination)이 이메일 전용 SNS 주제로 넘김. 실행 역할에 그 주제의 `sns:Publish` 권한을 줌. 이메일 전용 SNS 구성과 us-east-1 경보 처리는 decisions.md "경보 수신 경로" 결정에 따름(상태 대기) | 테스트 알림이 Discord에 도착, state·plan·환경 변수에 웹훅 URL 없음. 웹훅 URL을 일부러 잘못 넣은 테스트에서 이메일 전용 SNS 구독자가 실패 알림을 받음 |

## OBS-02 접근 로그·대시보드

**목적:** CloudFront 접근 로그를 남기고 핵심 지표를 한 화면에서 봄. 권장 항목

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | OBS-01, CDN-02 | 없음 | Phase 3 | 신규 | #13(R15) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| OBS-02-01 | CloudFront 접근 로그를 S3에 90일 보관 | 버킷 수명 주기 규칙에 90일 만료 설정 |
| OBS-02-02 | 대시보드 1개에 요청 수·5xx·RDS 메모리 표시 | 대시보드 접속 시 위젯 정상 표시 |

---

## 확인 필요 사항

- 경보 수신: 이메일(SNS 직접, GitHub 알림 주소)과 Discord(SNS→Lambda→웹훅) 둘 다로 확정(2026-10-02, decisions.md "경보 수신 이메일·임계값"). 2026-11-23에 Discord를 기본 경로로 하고 이메일은 Discord 전달 실패 때만 쓰는 방식이 제안됨(decisions.md "경보 수신 경로", 상태 대기). 확정 전에는 이메일 직접 구독이 현행 경로이며, 2026-12 시즌 동안 Lambda가 없으므로 계속 이 경로를 씀
- 경보 수신 이메일은 개인 주소 대신 팀 공용 Google 그룹 주소 1개로 바꿈(2026-11-24 시행, decisions.md "경보 수신 이메일 관리 방식"). 서울·us-east-1 경보 주제 모두 그룹 주소 구독 1개만 남고 개인 주소 구독은 삭제함(decisions.md "Phase 2 2차 apply 마감" 행의 예외). 수신자 교체는 그룹 멤버 추가·삭제로 하며 AWS·Terraform 변경이 필요 없음
- RDS 여유 메모리 경보 임계값: 초기 FreeableMemory 50MB로 시작(최근 14일 최소 75.6MB·평균 107.9MB·과거 저점 약 25MB 근거). 구축 중 알림 빈도 보고 조정
- 진행 순서: OBS-01-01~05(CloudWatch Agent·경보·SNS 이메일)를 먼저 끝내고 OBS-01-06(Discord Lambda)을 마지막에 함. plan 정책의 Lambda 코드 조회 거부 제거와 `archive` provider 추가는 2026-10-03 완료(decisions.md). 정책 제거는 bootstrap apply 후 적용되므로 Lambda를 state에 넣기 전에 apply 여부를 인프라 리드에게 확인함
- state 저장소는 Phase 1에서 준비됨(#25·#26). 경보 자원은 처음부터 Terraform으로 만듦
