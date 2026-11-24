# OBS 모니터링·경보 명세서

기준일 2026-11-24 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- 기존 계획에 없던 모니터링·경보를 새 자원으로 만듦
- 기존 자원을 건드리지 않고 새로 만들기만 하므로, state·backend·CI가 제대로 동작하는지 운영 자원 import 전에 확인하는 첫 작업으로 씀
- RDS 여유 메모리 부족(최저 약 25MB 실측)을 가장 먼저 감시함

**범위:** CloudWatch Agent, SNS 경보와 Discord 전달, 로그 그룹 보관 기간(앱 로그, RDS 로그, Lambda 로그), api 헬스체크(EventBridge·Lambda), 경보 추가·조건 변경, CloudFront 접근 로그, 대시보드
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
| OBS-01-03 | 앱 로그 90일 보관(2026-11-24 30일에서 변경. 장애·차단 사후 원인 조사에 요청 로그를 쓰기 위함), EC2 메모리·디스크 지표 수집. Agent 켜기 전에 로그 그룹을 먼저 만듦(자동 생성 시 무기한 보관) | 로그 그룹 보관 기간 90일 |
| OBS-01-04 | 헬스체크·5xx 비율·EC2 상태 검사·RDS 저장 공간·CPU 경보 추가 | SNS 구독 이메일로 각 경보 테스트 수신. 알림 경로(SNS 주제)마다 대표 경보 1개를 `set-alarm-state`로 울려 확인함: 서울 `boaz-alerts`는 RDS 여유 메모리 경보, us-east-1은 CloudFront 5xx 경보(2026-11-15 확인) |
| OBS-01-05 | 기존 운영 자원은 변경하지 않음. 콘솔로 만든 모니터링 자원은 import만 하고, 그 밖에는 새로 만들기만 함 | plan에 기존 자원 변경 없음, import와 생성만 존재 |
| OBS-01-06 | Discord 알림 Lambda(SNS→Lambda→웹훅). Lambda는 서울에 1개 두고, 서울 `boaz-alerts`와 us-east-1 `boaz-prod-alerts-us-east-1` 두 경보 주제가 구독함(us-east-1 주제는 리전을 건너 구독). Lambda 리소스 정책에 두 주제의 호출을 허용함. 코드는 저장소 소스를 `archive_file`로 zip하고 버킷은 쓰지 않음. 웹훅 URL은 서울 SSM `/boaz/obs/discord-webhook-url`(SecureString, AWS 관리형 키 `alias/aws/ssm`, 수동 등록, Terraform 관리 제외)을 실행 시 읽음. 실행 역할에 이 파라미터의 `ssm:GetParameter`와 `kms:Decrypt` 권한을 줌. Discord 응답이 2xx가 아니면(429 포함) Lambda가 예외를 던지고, Lambda의 실패 시 대상(on-failure destination)이 이메일 전용 SNS 주제로 넘김. 비동기 재시도 횟수(`maximum_retry_attempts`)는 0으로 두고 코드 안에서 1번만 다시 보냄(429면 `Retry-After`를 따름). 기본값(2번 더 재시도)이면 실패 메일이 몇 분 늦어짐. 이메일 전용 주제는 서울에 새로 만들고 구독자는 팀 공용 그룹 주소 1개임(`boaz-alerts`를 쓰면 실패 메시지가 다시 Lambda로 들어감). 실행 역할에 이 주제의 `sns:Publish` 권한을 줌. Lambda 로그 그룹(`/aws/lambda/<함수 이름>`)은 함수보다 먼저 Terraform으로 만들고 보관 기간을 정함(자동 생성 시 무기한 보관). 시즌 중에는 두 경보 주제의 그룹 직접 구독을 유지함(decisions.md "경보 수신 경로") | 이메일 전용 주제의 그룹 주소 구독이 확인됨(확인 메일은 apply 직후 그룹 소유자가 승인하며, 3일 안에 승인하지 않으면 만료됨). 서울과 us-east-1 대표 경보를 각각 `set-alarm-state`로 울려 Discord에 도착하고, 경보 주제의 그룹 직접 구독으로도 메일이 도착함. 웹훅 URL을 일부러 잘못 넣은 테스트에서 이메일 전용 주제 구독자가 실패 알림을 받음. state·plan·환경 변수에 웹훅 URL 없음. Lambda 로그 그룹 보관 기간이 정해져 있음 |
| OBS-01-07 | RDS 로그 그룹 2개(오류 로그, 느린 쿼리 로그) 90일 보관. 로그 그룹 이름은 RDS 인스턴스 식별자를 포함하므로 `docs/records/inventory.md`를 참조함. 보관 기간은 앱 로그와 다른 변수로 둠. 느린 쿼리 로그 그룹: Terraform으로 먼저 만든 뒤(보관 90일) RDB 담당이 로그 내보내기를 켬. 순서가 반대면 RDS가 무기한 보관 그룹을 먼저 만들고 Terraform 생성이 실패함. 오류 로그 그룹(지금 무기한 보관)은 import 후 보관 기간을 바꿈. 로그 그룹만 다루므로 RDS 인스턴스와 RDB import에는 영향 없음. 로그 내보내기 목록(오류, 느린 쿼리)은 RDB import 때 코드에 맞춰야 함(`docs/wbs/25-rdb.md` RDB-01-06) | 두 로그 그룹 보관 기간 90일, 느린 쿼리 로그 그룹이 내보내기 켜기 전에 존재 |
| OBS-01-08 | api 헬스체크: EventBridge 일정(서울, 1분 주기)으로 Lambda가 `/actuator/health`를 호출하고 결과를 지표로 남김. 경보는 3번 연속 실패일 때 울림(배포 때 약 50초 중단과 일정 실행 시각의 흔들림이 겹쳐 2번 연속 실패가 나는 것을 피함. 실제 장애는 약 3~4분 안에 알림). 점검이 멈춰 지표가 비는 것도 실패로 봄(`treat_missing_data = "breaching"`). Lambda 로그 그룹은 함수보다 먼저 Terraform으로 만들고 보관 기간을 정함 | 헬스체크 Lambda를 멈추거나 대상 주소를 틀리게 두면 경보가 Discord와 그룹 메일에 도착, Lambda 로그 그룹 보관 기간이 정해져 있음 |
| OBS-01-09 | 경보 추가·조건 변경. 추가: WAF 요청 수 제한 규칙(`RateLimitPerIP`) 차단 1건 이상, api CloudFront 502·504 5분 1건 이상, 앱 5xx 5분 1건 이상(요청 로그 지표 필터), 에이전트 데이터 누락(EC2-A 메모리·디스크 경보의 "데이터 부족" 상태), api 지연, www 4xx·5xx, 인증서 만료. 502·504 경보: api CloudFront 추가 지표를 켜야 지표가 생기고 켠 시점부터만 수집됨. 추가 지표는 obs 그룹에서 `aws_cloudfront_monitoring_subscription`(us-east-1)을 새로 만들어 켜고, 배포 자원은 바꾸지 않음. 이 자원은 plan 게이트의 보호 자원 목록에 없는 새 자원이라 G1·G4에 걸리지 않음. 요금은 지표 8개 × 월 $0.30(약 $2.4). 시즌 중에는 CloudFront를 바꾸지 않으므로 접수 시작 전 apply에서 켜지 못하면 502·504 경보도 시즌 뒤로 미룸. 건수는 metric math(비율 ÷ 100 × `Requests`, 근사값)로 구함. 데이터가 쌓이기 전에 만들므로 `treat_missing_data = "notBreaching"`으로 둠. 기존 api 5xx 비율 경보(OBS-01에서 Terraform으로 새로 만든 경보)는 시즌 뒤까지 유지함(decisions.md "api 5xx 경보 교체 방식"). 변경: import한 기존 경보 12개의 조건을 "최근 N개 중 M개 기준 초과"로 바꿈. 이 12개는 이름이 import 기준이라 이름을 바꾸지 않음(바꾸면 교체됨). CloudFront·WAF 경보는 us-east-1에 만들고 `boaz-prod-alerts-us-east-1`로 보냄 | 알림 주제마다 대표 경보 1개를 `set-alarm-state`로 울려 Discord와 그룹 메일 도착 확인. 502·504 지표가 CloudWatch에 실제로 수집되는지 확인함(`notBreaching`과 `set-alarm-state`만으로는 지표가 없어도 시험이 통과됨). 502·504 경보는 이 확인과 도착 시험이 끝나지 않으면 시즌 뒤로 미룸 |

OBS-01-05의 "기존 운영 자원은 변경하지 않음"은 OBS-01 import 단계의 기준임. OBS-01-07~09는 OBS-01에서 import하거나 만든 모니터링 자원(로그 그룹, 경보)을 고침

**적용 시점**(2026-11-24 기준)

| 시점 | 항목 |
| --- | --- |
| 2026-11-30 28기 서류 접수 시작 전(2026-11-25 apply 목표, 늦어도 2026-11-26 밤) | OBS-01-03 앱 로그 90일, OBS-01-07 RDS 로그 그룹, OBS-01-06 Discord 전달 Lambda(그룹 직접 구독 유지), OBS-01-08 api 헬스체크(후순위), OBS-01-09 중 api CloudFront 추가 지표·WAF 차단·502·504 경보 |
| 시즌 중(콘솔로 만들고 당일 기록, 시즌 뒤 Terraform PR로 반영) | OBS-01-09 중 에이전트 데이터 누락·앱 5xx·api 지연, OBS-02-02 대시보드 |
| 시즌 뒤 | 경보 이메일을 Discord 전달 실패 때만 받도록 바꾸기(확인 필요 사항 "경보 수신"), 기존 api 5xx 비율 경보 정리, 기존 경보 12개 조건 변경, OBS-01-09 중 www 4xx·5xx(SPA 경로 처리 변경 뒤)·인증서 만료(관리 주체 확인 뒤) |

- 접수 시작 전 항목은 apply 마감(2026-11-29, decisions.md "2026-12 시즌 apply 금지 유예") 안에서 `scripts/apply-group.sh`로 apply하고, apply가 끝날 때마다 다시 plan "No changes"를 확인함. 시험할 시간을 두려고 2026-11-25까지 apply하는 것을 목표로 함. season-up(2026-11-27) 뒤에는 apply하지 않음. 2026-11-26 밤까지 apply하지 못한 항목은 시즌 뒤로 미루며, 헬스체크(OBS-01-08)를 먼저 뺌
- 되돌리기: 시즌 전에는 G4 게이트 때문에 Terraform으로 자원을 지울 수 없음. Discord 전달 Lambda가 잘못 동작하면(중복 발송, 오류 반복 등) 콘솔에서 두 경보 주제의 SNS→Lambda 구독을 끊고 당일 decisions.md에 기록함. 그룹 직접 구독이 남아 있어 경보 수신은 이어짐. 헬스체크 경보가 잘못 울리면 경보 동작을 끈 뒤 EventBridge 일정을 끔(일정만 끄면 데이터 누락으로 경보가 울림). 시즌 중 obs apply가 불가피하면 그 전에 같은 내용을 코드에 먼저 반영함
- 시즌 중 콘솔 변경은 decisions.md "시즌 중 콘솔 변경 범위"를 따름. 새로 만드는 경보·지표 필터·대시보드는 허용. import한 경보 12개의 조건 변경은 장애 대응일 때만 하며, 다음 obs apply에서 코드 값으로 되돌아가므로 시즌 중 obs apply가 불가피하면 그 전에 콘솔 값을 `envs/prod/obs.tf` locals에 먼저 반영함. 모든 콘솔 변경은 당일 decisions.md에 대상, 바꾸기 전과 후의 값, 날짜, 이유를 기록함

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

- 경보 수신: Discord를 기본 경로로 하고, Discord 전달이 실패하면 이메일 전용 주제로 받음(2026-11-24 PO 결정, decisions.md "경보 수신 경로". "경보 수신 이메일·임계값"의 "이메일·Discord 둘 다" 결정을 대체함). 2026-12 시즌 동안에는 두 경보 주제의 그룹 직접 구독을 유지함. 실패 시 대상은 Lambda가 실행된 뒤 실패한 경우만 넘기고, SNS가 Lambda를 호출하지 못하는 경우(권한 제거, 호출 제한)는 잡지 못하기 때문임
  - 시즌 뒤 그룹 직접 구독을 빼기 전에 할 일
    - SNS가 Lambda를 호출하지 못한 경우: 리전별 SNS `NumberOfNotificationsFailed` 경보를 이메일 전용 주제로 보냄. CloudWatch 경보는 같은 리전 SNS만 호출하므로 us-east-1에도 이메일 전용 주제가 필요함. 새 주제는 같은 그룹 주소라도 확인 메일을 다시 승인해야 하며, 그룹 소유자인 인프라 담당이 승인함
    - 메시지 단위로 알리는 경로: 경보는 상태가 바뀔 때만 알리므로 실패 경보가 ALARM인 동안 생기는 다음 실패는 메일로 오지 않음. 또 `NumberOfNotificationsFailed`는 SNS가 Lambda를 호출하지 못한 경우만 셈. 구독 재시도 실패 대비(redrive DLQ)와 DLQ 깊이 경보 등으로 메시지마다 알리는 경로를 만듦
    - 연속 2건 전달 실패 시험. 위 시험을 모두 끝낸 뒤 경보 주제의 그룹 직접 구독을 뺌
- 경보 수신 이메일은 개인 주소 대신 팀 공용 Google 그룹 주소 1개(`boaz-tech@googlegroups.com`)로 바꿈(2026-11-24 시행, decisions.md "경보 수신 이메일 관리 방식"). 서울·us-east-1 경보 주제 모두 그룹 주소 구독 1개만 남고 개인 주소 구독은 삭제함(decisions.md "Phase 2 2차 apply 마감" 행의 예외). 수신자 교체는 그룹 멤버 추가·삭제로 하며 AWS·Terraform 변경이 필요 없음
- api 5xx 비율 경보를 502·504 건수 경보로 바꾸는 방식: 502·504 경보를 새로 만들고 기존 비율 경보는 시즌 뒤까지 유지함(2026-11-24 PO 결정, decisions.md "api 5xx 경보 교체 방식"). 기존 비율 경보 정리는 시즌 뒤 G4 해제·예외 결정 때 함
- 인증서 만료 경보: CloudFront 인증서(`*.bigdataboaz.com`, us-east-1 ACM, 자동 갱신 대상, 2027-03-09 만료)의 관리 주체를 확인한 뒤 경보를 걸지 정함
- RDS 여유 메모리 경보 임계값: 초기 FreeableMemory 50MB로 시작(최근 14일 최소 75.6MB·평균 107.9MB·과거 저점 약 25MB 근거). 구축 중 알림 빈도 보고 조정
- 진행 순서: OBS-01-01~05(CloudWatch Agent·경보·SNS 이메일)를 먼저 끝내고 OBS-01-06(Discord Lambda)을 마지막에 함. plan 정책의 Lambda 코드 조회 거부 제거와 `archive` provider 추가는 2026-10-03 완료(decisions.md). bootstrap apply 완료(2026-10-03, plan 정책 v2에서 `lambda:GetFunction` 거부 제거 확인)
- state 저장소는 Phase 1에서 준비됨(#25·#26). 경보 자원은 처음부터 Terraform으로 만듦
