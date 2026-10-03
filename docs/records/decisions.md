# 결정·확인 필요 레지스터

Terraform 이전 작업에서 **결정이 필요한 것**과 **팀에 확인이 필요한 것**을 한 곳에 모은 표. WBS(`docs/wbs/00-wbs.md`)는 진행 관리만 담고, 결정·확인 사항은 이 문서가 기준

- 분류: `결정`(선택지 중 하나를 정해야 함) / `확인`(사실이나 일정을 알아봐야 함)
- 상태: `대기` / `조사 중` / `완료`
- 결정 항목은 기한이 지나면 기본안을 채택함. 결정 주체는 별도 표기가 없으면 [추정].
- 상태가 `대기`인 결정이 막는 티켓은 추정값으로 import·apply하지 않음
- 노션에는 이 표를 데이터베이스로 옮겨 상태·기한으로 걸러 봄

## 레지스터

| 항목 | 분류 | 상태 | 기본안·확인할 내용 | 결정·확인 주체 | 기한 | 막는 티켓 | 조사 결과·비고 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| state 버킷·키 | 결정 | 완료 | 전용 신규 버킷, 키 `envs/prod/terraform.tfstate` | 인프라 담당 | 2026-10-02 | STA-03, STA-04 | 2026-09-27 기본안으로 확정. 잠금은 S3 자체 잠금(`use_lockfile`), 암호화는 SSE-S3(AES256, KMS 키 삭제 시 복구 불가 위험 회피). bootstrap state도 같은 버킷 `bootstrap/terraform.tfstate`로 옮김(최초 apply만 로컬, 유실 시 import로 복구 가능). 이전 버전은 90일 뒤 만료(최근 20개 보관), 미완료 멀티파트 업로드 7일 뒤 중단, 만료된 삭제 마커(`.tflock`) 정리. 버킷 태그 `Environment = "shared"`(모든 환경 공용). 환경 추가 시 `envs/<환경>/terraform.tfstate` 키로 같은 버킷 사용. 기존 버킷 중 state 후보 없음 |
| EC2-B 제어 방식 | 결정 | 완료 | `aws_ec2_instance_state`로 running·stopped 상태 제어, ASG 전환 안 함 | 인프라 담당 + 백엔드 리드 | 2026-10-02 | CMP-01 | 2026-10-02 채택. ASG는 launch template·ASG 신규 생성과 인스턴스 교체가 필요해 import 목표(plan "No changes")와 비목표 "구조 변경"(`docs/overview/migration-plan.md` 1절)에 어긋남. 현재 launch template·ASG 없음. `season_capacity`가 전원뿐 아니라 CodeDeploy 대상 태그(`app=boaz-api`)·Target Group 등록 대상도 함께 제어하므로, 기동·재배포·종료 순서는 "EC2-B 기동·재배포 연동" 확인 항목에서 정함 |
| 관리 대상 버킷·레코드 | 결정 | 완료 | 서비스 버킷만 현행 그대로 관리 대상으로 import, 미사용 추정 버킷·레코드는 관리 제외(삭제 아님)로 기록 | 운영진 + 인프라 담당 | 2026-10-09 | STO-01, STO-02 | 2026-10-02 채택, 2026-10-03 아카이빙 버킷 누락 정정. 관리 대상 5개: 운영 프론트·관리자 프론트·지원서·배포 번들·아카이빙 버킷. 관리 제외: 레거시 웹사이트·dev 웹사이트·구 홈페이지·설문 버킷, dev 프론트 버킷, Route53 `dev`·`dev-back` A 레코드, 미사용 OAI·고아 인증서 검증 CNAME. 제외는 Terraform 미관리를 뜻하며 삭제하지 않음. 삭제·재사용은 운영진 확인 후 별도 PR |
| Network ACL 관리 방식 | 결정 | 완료 | 현행 그대로 import(`aws_default_network_acl`) | 인프라 담당 | 2026-10-09 | NET-01 | 2026-10-02 채택. 기본 NACL 1개만 존재하고 규칙 변경 없음. import 목표(현행 보존)에 맞춰 그대로 편입, 규칙 변경은 별도 PR |
| WAF WebACL 관리 방식 | 결정 | 완료 | CloudFront에서 기존 WebACL을 참조만 함, WebACL 자체 import는 보류 | 인프라 담당 | 2026-10-16 | CDN-02, CDN-03 | 2026-10-03 기본안으로 확정. 3개 배포 모두 CloudFront 자동 생성 WebACL 연결(us-east-1, Firewall Manager 관리 아님). 3개 모두 관리형 규칙 그룹 3종 적용, api WebACL에는 사용자 정의 규칙 `RateLimitPerIP` 추가 있음(참조만 하므로 코드 밖에 남음). 요금제 묶음 여부는 CLI로 확인되지 않아 콘솔 확인 필요(결정에는 영향 없음, import 재검토 시 사용) |
| 앱 시크릿 SecureString 범위 | 결정 | 완료 | 잔여 2개(`DB_URL`, `DB_USERNAME`)는 현행 유지, 후속 이슈로 분리 | 백엔드 리드 | 2026-10-16 | IAM-03, IAM-04 | 2026-10-03 기본안으로 확정. SSM 파라미터 26개 중 SecureString 6개(비밀값), String 20개 확인. 전환은 후속 이슈에서 백엔드 `load-ssm-env.sh`(파라미터별 복호화 조회)와 EC2 역할의 KMS 권한 영향을 확인한 뒤 진행 |
| 공개 읽기 S3 버킷 | 결정 | 완료 | 공개 읽기 정책을 현행 유지로 import, 변경은 별도 PR | 운영진 | STO-01 전 | STO-01 | 2026-10-02 채택. 아카이빙 버킷과 구 홈페이지 버킷이 공개 읽기 정책. import는 현행 보존이 원칙이라 정책 그대로 편입, 공개 범위 변경은 별도 승인·PR |
| 프론트 버킷 퍼블릭 차단 | 결정 | 완료 | 이번 import에서는 현행 유지(퍼블릭 차단 적용 안 함), 변경은 별도 PR | 인프라 담당 | STO-01 전 | STO-01 | 2026-10-02 채택. 실제 공개는 아니나 퍼블릭 액세스 차단이 모두 꺼진 상태. import는 현행 보존이 원칙이라 그대로 편입, 차단 적용은 별도 승인·별도 PR |
| 지원서 버킷 수명 주기 | 결정 | 완료 | 30일 만료 그대로 코드에 반영 | 운영진 | STO-01 전 | STO-01 | 2026-10-02 채택. 조회로 지원서 버킷에 30일 후 자동 삭제 수명 주기 확인. 현행 그대로 import |
| SSH 접근 방식 | 결정 | 완료 | 현행 유지(pem key SSH + 개인 IP 2개 허용 SSH 보안 그룹)로 import. Session Manager 전환은 별도 PR | 인프라 담당 + 운영진 | NET-01 전 | NET-01 | 2026-10-02 채택. EC2-A·B 모두 key pair(`boaz_codedeploy`)로 pem SSH 사용 중. SSH 보안 그룹은 개인 IP 2개(/32)로만 22번 허용(전체 공개 아님). import는 현행 보존이 원칙이라 그대로 편입. Session Manager는 Online 상태라 가능하나 전환은 범위 밖(별도 승인·PR). 개인 IP는 코드·문서에 적지 않고 조사값으로만 확인 |
| apply 승인자 | 결정 | 대기 | 2명 이상(GitHub Environment reviewer) | 운영진 | 2027-01-31 | STA-11 | |
| property 테스트 범위 | 결정 | 완료 | 판정 로직은 고정 입력 테스트, hypothesis는 P1·P6만 적용 | 인프라 담당 + PM | 2026-10-09 | STA-07 | 2026-10-02 채택(인프라 담당이 PM 겸임). 설계대로 전면 적용은 비용이 크고, 전부 빼면 판정 로직 예외를 놓침. #32·#33에 이 범위로 구현 완료 |
| 최종 인수 판정 방식 | 결정 | 대기 | 자동 스크립트 vs 체크리스트와 명령 출력 캡처 | 인프라 담당 + PM | Phase 5 전 | OPS-07 | |
| CDN-03 지연 시 대응 | 결정 | 대기 | 관리자 페이지 오픈 연기 vs 콘솔로 먼저 적용 후 코드 반영 | PM + 운영진 | Phase 2 2차 중 | CDN-03 | 관리자 페이지 12월 오픈 목표 |
| 구 스크립트 백업 이관 | 결정 | 대기 | `backend/infra/scripts/`의 구 운영 스크립트(`season-up.sh`·`season-down.sh`·`cf_set_origin.py`·`register-ssm-params.sh`)를 product-infra로 백업 이관할지. 이관 시 공개 저장소라 자원 ID·계정 ID·개인 IP를 먼저 제거 | 인프라 담당 | OPS-08 중 | OPS-08 | 2026-10-02 제기. 아이디어 단계. backend README 수정 동의는 받음. 그대로 복사 금지(민감 정보 포함 가능), `scripts/check-sensitive.sh` 통과 후에만 커밋 |
| dev 환경 신설 | 결정 | 대기 | 필요할 때만 dev EC2를 올려 검증 후 prod 배포하는 일회용 모델 채택 여부. 채택 시 Phase 2 뒤 별도 Epic | 인프라 담당 + 백엔드 리드 + 운영진 | Phase 2 마무리 뒤 | 없음 | 현재 비목표(`docs/overview/migration-plan.md` 1절). 기술 검토 문서는 노션에 둠. state 구조는 환경 추가 가능(STA-03) |
| CloudTrail 존재 여부 | 확인 | 완료 | 존재 여부 확인. 없으면 콘솔 변경 추적 활성화 여부 결정 | 인프라 담당 | 2026-10-09 | 없음 | 2026-10-02 조사: CloudTrail trail 없음(서울·us-east-1 모두 0개). 콘솔 수동 변경 추적이 안 되는 상태. 활성화 여부는 Phase 3 이후 별도 검토(지금 import 작업에는 영향 없음) |
| 모집 시즌 전환 공통 지침 | 결정 | 완료 | season-up은 리크루팅 월 첫째 주를 변동 가능 버퍼로 두고 둘째 주부터 동결. season-down은 리크루팅 월에는 유지하고 다음 달 첫째 주에 전환 | 운영진 + 인프라 담당 | 2026-10-02 | Phase 2 마감, OPS-01 | 2026-10-02 채택. 특정 날짜가 아니라 매 리크루팅마다 적용하는 규칙. 구체 날짜는 마이그레이션 일정(`docs/wbs/01-schedule.md`)에서 관리 |
| 동결 종료 시점 | 결정 | 완료 | season-down 후 3일 | 운영진 | 2026-10-02 | OPS-01 | 2026-10-02 채택. 기본 3일 유지 |
| 2027-01 출결 기능 배포 주 | 확인 | 대기 | 배포 주, RDS 유지보수 시간(목요일 20:00 UTC)과 겹치는지 | 운영진 + 백엔드 리드 | 2026-09-30 | OPS-03 | |
| 참여 인원·주당 투입 시간 | 확인 | 완료 | Phase 2 참여 인원과 시간 | 인프라 담당 + 운영진 | 2026-09-30 | Phase 2 범위 | 2026-10-02 참여 인원 5명 확인(1명 초과라 Phase 2 2차 동결 전 진행), 파트 배정은 `00-wbs.md` 배정표. 주당 투입 시간은 별도 관리하지 않음 |
| Terraform 실행 자격 증명 | 확인 | 완료 | 장기 액세스 키인지 여부 | 인프라 담당 | 2026-10-09 | STA-05 | 2026-09-27 확인: 로컬은 `aws login` 세션·MFA, 장기 액세스 키 없음. CI는 GitHub OIDC plan 역할(`bootstrap/ci_plan_role.tf`) (#31) |
| PR plan 결과 공개 범위 | 결정 | 완료 | PR 코멘트·로그에는 action별 개수와 자원 주소만, plan 원문·plan JSON은 출력·업로드 안 함 | 인프라 담당 | Phase 2 준비 | STA-05 | 공개 저장소라 Actions 로그·artifact·코멘트를 누구나 봄. plan JSON에는 sensitive 값도 평문으로 들어감 (#31) |
| dev 프론트 배포 워크플로 | 확인 | 완료 | 최근 실행 성공 여부 | 인프라 담당 | 2026-10-09 | OPS-06 | 2026-10-02 조사: frontend 레포에 `deploy-dev.yml` 없음(`deploy-www.yml`만 존재), 최근 dev 배포 실행 3건 모두 실패. 연결 CloudFront 배포가 삭제돼 복구 불가 상태. dev 프론트 버킷은 관리 제외(STO), 워크플로 정리는 OPS-06에서 별도 처리 |
| 경보 수신 이메일·임계값 | 확인 | 완료 | SNS 수신 주소, RDS 여유 메모리 기준값 | 운영진 | Phase 2 준비 전 | OBS-01 | 2026-10-02 결정. 수신은 이메일(SNS 직접, GitHub 알림 주소)과 Discord(SNS→Lambda→웹훅) 둘 다. SNS·Lambda 모두 이 양에서는 무료 범위. RDS 여유 메모리 경보 초기 임계값은 50MB(FreeableMemory, 최근 14일 최소 75.6MB·평균 107.9MB·과거 저점 약 25MB 근거), OBS-01 구축 중 알림 빈도 보고 조정 |
| 레거시 버킷 소유자·사용 여부 | 확인 | 완료 | 소유자, 계속 쓰는지, 아카이빙 버킷 버전 관리 필요 여부 | 운영진 | STO-02 전 | STO-02 | 2026-10-02 처리. 레거시·설문 버킷은 관리 제외로 두므로 사용 여부와 무관하게 import 범위 밖. 삭제·정리는 별도 PR에서 운영진 확인 후 진행 |
| RDS 암호화 키·파라미터 값 | 확인 | 완료 | 암호화 키 종류(AWS 관리형/직접 생성), 파라미터 그룹 실제 값 | 인프라 담당 | RDB-01 전 | RDB-01 | 2026-10-02 조사. 암호화 켜짐, 키는 AWS 관리형 기본 RDS 키(`alias/aws/rds`, 고객 생성 키 아님)라 Terraform 키 관리 불필요. 파라미터 그룹 `boaz-prod-mysql84`에서 기본값과 다른 값은 `time_zone = Asia/Seoul`(immediate) 하나뿐. 엔진 MySQL 8.4.11. import 시 조사값 그대로 맞춰 교체 방지 |
| plan 정책 Lambda 코드 조회 거부 | 결정 | 완료 | `lambda:GetFunction` 거부를 plan 정책에서 제거 | 인프라 담당 | OBS 착수 전 | OBS-01 | 2026-10-03 확정. Lambda가 state에 들어가면 refresh가 이 호출을 써서 CI·팀원 plan이 모두 실패함. 코드가 공개 저장소에 있어 코드 링크 노출 위험이 작음. 정책은 CI 역할·읽기 전용 그룹 공용이라 bootstrap apply 후 적용 |
| Discord 알림 Lambda 코드 위치 | 결정 | 완료 | 저장소 소스를 `archive_file`로 zip해 배포, 별도 S3 버킷 없음 | 인프라 담당 | OBS 착수 전 | OBS-01 | 2026-10-03 확정. `archive` provider를 `envs/prod/versions.tf`와 잠금 파일에 추가함(STA 담당 수정) |
| Discord 웹훅 URL 보관 방식 | 결정 | 완료 | SSM SecureString에 수동 등록, Lambda가 실행 시 읽음. Terraform으로 import·관리하지 않음 | 인프라 담당 | OBS 착수 전 | OBS-01 | 2026-10-03 확정. 환경 변수·Terraform 변수로 넣으면 노출되거나 state에 남음. Lambda 실행 역할의 SecureString 복호화(KMS) 권한은 OBS-01-06에서 확인 |
| EC2-B 사전 점검 | 확인 | 대기 | 12월 시즌 전 기동·패치·에이전트 점검 날짜, 공인 IPv4 과금 비용표 반영 | 인프라 담당 | Phase 2 2차 중 | CMP-03 | |
| EC2-B 기동·재배포 연동 | 확인 | 완료 | 재배포 성공 판정·서비스 자동 기동은 기존 CodeDeploy 메커니즘 사용. 전환 중 CI 배포 동결 방법은 백엔드 리드와 2차 전 확정 | 백엔드 리드 | CMP-03, SEA-02 전 | CMP-03, SEA-02 | 2026-10-02 backend 레포 조사. (1) 재배포 성공 판정: CodeDeploy ValidateService 훅 `validate_service.sh`가 `/actuator/health` 200을 10회 확인, cd.yml이 `deployment-successful` 대기 — 기존 판정 사용. (2) 서비스 기동: `boaz.service`가 enable+`WantedBy=multi-user.target`이라 재부팅 시 자동 기동, `application_start.sh`가 `systemctl enable`. 기동 후 `codedeploy-agent` 상태 1회 점검만 런북에 둠. (3) 전환 중 동결: cd.yml이 main CI 완료 시 AllAtOnce 자동 배포라, 전환 중 main 머지·수동 배포 금지 필요(방법은 백엔드 리드와 확정). (4) OPS-08 backend README 수정 동의 받음(2026-10-02) |
| EC2-A EIP 처리 | 결정 | 완료 | 기존 EIP와 연결을 import, `prevent_destroy` | 인프라 담당 | 2026-10-02 | CMP-01 | 조사로 이미 연결 확인 |
| admin CloudFront import 포함 | 결정 | 완료 | 기존 자원 import에 포함 | 인프라 담당 | 즉시 | CDN-01 | 계획서 비목표(신규 환경 구성)와 별개 |
| 브랜치 전략 | 결정 | 완료 | dev → main | 인프라 담당 | 2026-09-26 | 없음 | README 협업 규약·base 검사 workflow. apply 실행 브랜치는 STA-11에서 확정 |
| CodeDeploy 태그 방식 | 결정 | 완료 | 현행 태그 방식(`ec2_tag_set`) 유지 | 백엔드 리드 | 2026-11-06 | DEP-01, DEP-02 | 실측과 일치해 현행 유지로 확정. backend#214(배포 방식 변수화)가 배포 그룹 설정을 바꾸면 다시 검토 |
| AWS provider 버전 | 결정 | 완료 | 6.x(`>= 6.0.0, < 7.0.0`), 잠금 파일로 버전 고정 | 인프라 담당 | Phase 1 중 | STA-02 | 5.x는 2025-06 이후 갱신 없음. 신규 코드라 6.0 호환성 변경(`aws_eip`의 `domain`, `aws_instance.user_data` 평문 저장 등) 영향 없음. 업그레이드는 전용 PR에서 plan "No changes" 확인, 시즌 동결 중 금지 (#24) |
| default_tags 적용 시점 | 결정 | 완료 | envs/prod는 모든 그룹 import와 최종 일치 확인(STA-09) 뒤 태그 전용 PR로 적용, bootstrap은 처음부터 적용 | 인프라 담당 | Phase 1 중 | STA-02, STA-09 | 기존 자원에 태그가 없어 import 단계에 적용하면 모든 plan에 태그 변경이 생겨 "No changes"를 맞출 수 없음 (#24) |
| 시즌 값 관리 위치 | 결정 | 완료 | `envs/prod/season.auto.tfvars`를 커밋(.gitignore 예외), 변수 기본값 없음 | 인프라 담당 | Phase 2 준비 | SEA-01 | 시크릿·자원 ID가 없고, 커밋해야 CI plan이 현재 시즌 값을 알 수 있고 시즌 전환이 PR로 남음. 기본값이 있으면 시즌 중 누락 시 ALB 삭제 plan이 생김 (#34) |
| CDN 선행 분리 | 결정 | 완료 | CDN-01·CDN-02 1단계·CDN-03의 선행을 CMP-02에서 STO-01로 변경, api 배포만 CDN-02 2단계로 CMP-02 이후 | 인프라 담당 | Phase 2 1차 착수 전 | CDN-01, CDN-02, CDN-03 | 2026-10-02 확정. admin·www CloudFront origin이 S3이고 평시 ALB가 없음을 조회로 확인. CDN-03이 CMP-01·CMP-02를 기다리지 않음 (#35) |
| storage·cdn 참조 방향 | 결정 | 완료 | cdn이 storage output을 참조하고, storage 버킷 정책의 CloudFront 배포 ARN은 data source로 조회 | 인프라 담당 | STO-01 전 | STO-01, CDN-02 | 2026-10-02 확정. 프론트엔드 버킷 정책 조건(`AWS:SourceArn`)에 배포 ARN이 있어 양방향 output 참조 시 순환 참조 (#35) |
| 팀원 AWS 접근 방식 | 결정 | 완료 | IAM 사용자 + 각자 액세스 키로 CLI 사용(막지 않음). MFA 강제는 하지 않음 | 인프라 담당 | Phase 2 1차 착수 전 | #44 | 2026-10-02 확정. 급한 착수 우선, 장기 키 허용·MFA 생략은 공개 저장소 기준상 트레이드오프로 인지. IAM Identity Center는 미도입(계정 1개·단기 작업이라 과함) |
| 팀원 권한 범위 | 결정 | 완료 | 읽기 전용(`ReadOnlyAccess` + state 접근, 시크릿·S3객체·복호화 Deny). 그룹 `terraform-readonly` | 인프라 담당 | Phase 2 1차 착수 전 | #44 | 2026-10-02 확정·적용. import·plan은 조회만 필요. 쓰기·apply 없음. 그룹·정책은 bootstrap 코드, 사용자는 코드 밖(이름 비공개) |
| apply 실행 주체 | 결정 | 완료 | 관리자(Admin 그룹, 운영진 3명)가 apply. 읽기 전용 팀원 2명은 재조사·plan까지 | 인프라 담당 | Phase 2 1차 착수 전 | #44, STA-11 | 2026-10-02 확정. state 1개라 동시 apply 위험·보호 자원 많음. apply는 한 번에 한 그룹만. OBS 생성 apply·IAM-01 Role 변경 등 보호 자원 쓰기는 관리자가 수행. Phase 3 STA-11에서 승인 후 자동 apply로 전환 검토 |
| 운영진 1명 관리자 권한 | 결정 | 완료 | 관리자(Admin 그룹) 유지 | 인프라 담당 + 해당 운영진 | 2026-10-02 | #44 | 당초 읽기 전용 검토했으나, DB 스냅샷(RDB-01-04) 등 운영 편의로 관리자 유지. 웹사이트 이미지 업로드는 앱이 자기 역할로 처리해 해당 운영진 개인 권한과 무관 |
| apply 우선순위 | 결정 | 완료 | STO-01 → CDN-02 1단계 → CDN-03 줄과 IAM-02 → CMP-01 → CMP-02 줄을 먼저, 나머지 그룹은 그 사이에 apply | 인프라 담당 | Phase 2 1차 착수 전 | Phase 2 전체 | 2026-10-02 확정. `import-procedure.md` 2절 (#35) |

## 참고

- 조사 근거: `docs/records/inventory.md`(조사 시점 2026-09-23)
- 각 명세서(`docs/wbs/*.md`)의 "확인 필요 사항"은 해당 티켓 작업 중 확인할 세부 사항. 일정·범위에 영향을 주는 항목은 이 레지스터로 올림
