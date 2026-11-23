# OBS 모니터링·경보 명세서

기준일 2026-11-24 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- 기존 계획에 없던 모니터링·경보를 새 자원으로 만듦
- 기존 자원을 건드리지 않고 새로 만들기만 하므로, state·backend·CI가 제대로 동작하는지 운영 자원 import 전에 확인하는 첫 작업으로 씀
- RDS 여유 메모리 부족(최저 약 25MB 실측)을 가장 먼저 감시함

**범위:** CloudWatch Agent, SNS 경보와 Discord 전달, 로그 그룹 보관 기간(앱 로그, RDS 로그), api 헬스체크(EventBridge·Lambda), 경보 조건 변경, CloudFront 접근 로그, 대시보드
**범위 밖:**
- 시즌 ALB 경보 자동화(12월은 수동 생성 또는 생략)
- WAF 로그 설정: WAF 웹 ACL은 참조만 하므로 콘솔로 적용하고 `docs/records/decisions.md`에 기록함("WAF WebACL 관리 방식"). WAF 로그 버킷은 STO에서 관리함
- RDS 느린 쿼리 로그 켜기(파라미터 그룹, 로그 내보내기): RDB 소관. 로그를 받을 로그 그룹만 OBS에서 만듦(OBS-01-07)

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
| OBS-01-03 | 앱 로그 90일 보관(2026-11-24 30일에서 변경. 요청 로그로 시즌 간 비교와 사후 원인 조사를 하기 위함), EC2 메모리·디스크 지표 수집. Agent 켜기 전에 로그 그룹을 먼저 만듦(자동 생성 시 무기한 보관) | 로그 그룹 보관 기간 90일 |
| OBS-01-04 | 헬스체크·5xx 비율·EC2 상태 검사·RDS 저장 공간·CPU 경보 추가 | SNS 구독 이메일로 각 경보 테스트 수신. 알림 경로(SNS 주제)마다 대표 경보 1개를 `set-alarm-state`로 울려 확인함: 서울 `boaz-alerts`는 RDS 여유 메모리 경보, us-east-1은 CloudFront 5xx 경보(2026-11-15 확인) |
| OBS-01-05 | 기존 운영 자원은 변경하지 않음. 콘솔로 만든 모니터링 자원은 import만 하고, 그 밖에는 새로 만들기만 함 | plan에 기존 자원 변경 없음, import와 생성만 존재 |
| OBS-01-06 | Discord 알림 Lambda(SNS→Lambda→웹훅). 코드는 저장소 소스를 `archive_file`로 zip하고 버킷은 쓰지 않음. 웹훅 URL은 수동 등록한 SSM SecureString을 실행 시 읽음(Terraform 관리 제외). 실행 역할의 복호화 권한 확인. 전달 실패 대비: Discord 응답이 2xx가 아니면 Lambda가 오류를 내고, 실패 시 전달 대상(on-failure destination)으로 원래 알림을 이메일 전용 SNS 주제에 넘김. 비동기 재시도는 0회로 두고 코드 안에서 한 번만 다시 보냄(요청 제한이면 `Retry-After`를 따름). 두 알림 주제(서울 `boaz-alerts`, `boaz-prod-alerts-us-east-1`)의 기존 이메일 구독은 정리함 | 테스트 알림이 Discord에 도착, state·plan·환경 변수에 웹훅 URL 없음. 웹훅 URL을 일부러 틀리게 둔 상태에서 테스트 알림이 이메일로 도착 |
| OBS-01-07 | RDS 로그 그룹 90일 보관. 느린 쿼리 로그 그룹은 RDB 담당이 로그 내보내기를 켜기 전에 먼저 만듦(자동 생성 시 무기한 보관). 오류 로그 그룹(`/aws/rds/instance/boaz-prod-db/error`, 지금 무기한 보관)은 import 후 보관 기간을 바꿈. 로그 그룹만 다루므로 RDS 인스턴스와 RDB import에는 영향 없음 | 두 로그 그룹 보관 기간 90일, 느린 쿼리 로그 그룹이 내보내기 켜기 전에 존재 |
| OBS-01-08 | api 헬스체크: EventBridge 일정(서울, 1분 주기)으로 Lambda가 `/actuator/health`를 호출하고 결과를 지표로 남김. 경보는 2번 연속 실패일 때 울리고, 점검이 멈춰 지표가 비는 것도 실패로 봄. 배포 때 약 50초 중단에는 울리지 않음 | 헬스체크 Lambda를 멈추거나 대상 주소를 틀리게 두면 경보가 Discord에 도착 |
| OBS-01-09 | 경보 추가·조건 변경. 추가: WAF 요청 수 제한 규칙(`RateLimitPerIP`) 차단 1건 이상, api CloudFront 502·504 5분 1건 이상, 앱 5xx 5분 1건 이상(요청 로그 지표 필터), 에이전트 데이터 누락(EC2-A 메모리·디스크 경보의 "데이터 부족" 상태), api 지연, www 4xx·5xx, 인증서 만료. 변경: import한 기존 경보 조건을 "최근 N개 중 M개 기준 초과"로 바꿈. 경보 이름은 import 기준이라 바꾸지 않음(바꾸면 교체됨). CloudFront·WAF 경보는 us-east-1에 만들고 `boaz-prod-alerts-us-east-1`로 보냄 | 알림 주제마다 대표 경보 1개를 `set-alarm-state`로 울려 Discord 도착 확인 |

OBS-01-05의 "기존 운영 자원은 변경하지 않음"은 OBS-01 import 단계의 기준임. OBS-01-07~09는 OBS-01에서 import한 모니터링 자원(로그 그룹, 경보)을 고침

**적용 시점**(2026-11-24 기준, 순서와 날짜는 PO 검토 뒤 확정)

| 시점 | 항목 |
| --- | --- |
| 2026-11-30 28기 서류 접수 시작 전 | OBS-01-03 앱 로그 90일, OBS-01-07 느린 쿼리·오류 로그 그룹, OBS-01-06 전달 실패 시 이메일, OBS-01-08 api 헬스체크, OBS-01-09 중 WAF 차단·502·504 경보 |
| 시즌 중(콘솔로 바꾸고 당일 기록, 시즌 뒤 Terraform PR로 반영) | OBS-01-09 중 기존 경보 조건 변경·에이전트 데이터 누락·앱 5xx·api 지연, OBS-02-02 대시보드 |
| 시즌 뒤 | OBS-01-09 중 www 4xx·5xx(SPA 경로 처리 변경 뒤), 인증서 만료(관리 주체 확인 뒤) |

## OBS-02 접근 로그·대시보드

**목적:** CloudFront 접근 로그를 남기고 핵심 지표를 한 화면에서 봄. 권장 항목

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | OBS-01, CDN-02 | 없음 | Phase 3 | 신규 | #13(R15) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| OBS-02-01 | CloudFront 접근 로그를 S3에 90일 보관 | 버킷 수명 주기 규칙에 90일 만료 설정 |
| OBS-02-02 | 대시보드 1개. 맨 위에 사용자 증상(가용성, 지연, WAF 차단)과 SLO, 그 아래 계층별 상세(CloudFront → WAF → 애플리케이션 → EC2 → RDS)를 둠. EC2 CPU 크레딧 포함. API별 오류 수·처리 시간은 Logs Insights 위젯으로 봄. 시즌 중 콘솔로 만들고 시즌 뒤 Terraform에 반영 | 대시보드 접속 시 위젯 정상 표시 |

---

## 확인 필요 사항

- 경보 수신: 평소에는 Discord(SNS→Lambda→웹훅)로만 받고, 이메일은 Discord 전달 실패 때만 받음(OBS-01-06). 2026-10-02 "이메일과 Discord 둘 다" 결정을 2026-11-24 변경함(#102, PO 검토 중, decisions.md "경보 수신 이메일·임계값"). `alert_emails` 키는 이메일 전용 SNS 주제의 수신 주소로 씀
- api 5xx 비율 경보를 502·504 건수 경보로 바꾸는 방법(2026-11-26까지 PO 확인): 경보 이름 `boaz-prod-cloudfront-api-5xx-rate-high`가 코드에 고정돼 있어 이름을 바꾸면 경보가 교체되고, "Phase 2 게이트 범위" 결정의 G4가 이 교체를 막음
  - (a) 502·504 경보를 새로 만들고, 옛 경보는 `removed` 블록으로 state에서만 뺀 뒤 콘솔에서 지움. 이름과 내용이 맞지만 콘솔 삭제가 한 번 필요함
  - (b) 이름은 그대로 두고 지표만 502·504 건수로 바꿈. 교체가 없지만 이름과 내용이 달라짐
- 인증서 만료 경보: CloudFront 인증서(`*.bigdataboaz.com`, us-east-1 ACM, 자동 갱신 대상, 2027-03-09 만료)의 관리 주체를 확인한 뒤 경보를 걸지 정함
- RDS 여유 메모리 경보 임계값: 초기 FreeableMemory 50MB로 시작(최근 14일 최소 75.6MB·평균 107.9MB·과거 저점 약 25MB 근거). 구축 중 알림 빈도 보고 조정
- 진행 순서: OBS-01-01~05(CloudWatch Agent·경보·SNS 이메일)를 먼저 끝내고 OBS-01-06(Discord Lambda)을 마지막에 함. plan 정책의 Lambda 코드 조회 거부 제거와 `archive` provider 추가는 2026-10-03 완료(decisions.md). 정책 제거는 bootstrap apply 후 적용되므로 Lambda를 state에 넣기 전에 apply 여부를 인프라 리드에게 확인함
- state 저장소는 Phase 1에서 준비됨(#25·#26). 경보 자원은 처음부터 Terraform으로 만듦
