# 결정 필요 항목 및 승인 게이트

미결정 항목과 그 결정 전까지 진행 불가한 작업을 기록. 각 항목은 결정되기 전까지 연관 자원의 코드 편입(import)·apply를 차단.

상태 표기: `결정 대기` / `결정 완료`

## 미결정 항목

| 항목 | 상태 | 결정 필요 주체 | 필요 시점 | 차단되는 작업 |
|---|---|---|---|---|
| Terraform state 저장소 버킷·키 | 결정 대기 | [확인 필요] | 상태 저장소 구성 착수 전 | bootstrap, envs/prod backend 초기화 |
| EC2-A 기존 EIP·연결(association)을 managed로 import할지 | 결정 대기 | [확인 필요] | 서버 코드 편입 전 | compute 모듈, CloudFront api origin |
| EC2-B 시작·중지 제어 방식 (`aws_ec2_instance_state` vs ASG). 현재 launch template·ASG 없음 | 결정 대기 | [확인 필요] | 서버 코드 편입 전 | compute 모듈, season_mode 전환 |
| 앱 파라미터 보강 범위: secret 6개는 이미 SecureString(`alias/aws/ssm`). 남은 String `DB_URL`·`DB_USERNAME` 전환 여부, CMK 전환 여부 | 결정 대기 | [확인 필요] | 파라미터 코드 편입 전 | params 모듈 |
| 코드 반영(apply) 승인자 지정 (GitHub Environment reviewer) | 결정 대기 | [확인 필요] | apply workflow 활성화 전 | terraform-apply workflow |
| 인프라 저장소 브랜치 전략(조직 표준 dev → main 적용 여부) | 결정 대기 | [확인 필요] | PR CI 구성 전 | PR·apply workflow 트리거 |

## 조사에서 확인된 결정 필요 사항

| 항목 | 조사 결과 | 결정 필요 내용 | 상태 |
|---|---|---|---|
| CloudFront WAF WebACL | 3개 배포 모두 `CreatedByCloudFront-*` WebACL 연결 (us-east-1) | WebACL을 import해 관리할지, `web_acl_id`로 ARN만 참조할지. CloudFront 요금제 연동 여부 확인 | 결정 대기 |
| 공개 읽기 S3 버킷 | `boaz-archiving`(managed 대상), `boazweb`이 `Principal:*` 공개 읽기 | 의도된 공개인지 확인, 아니면 차단 방식 결정 | 결정 대기 |
| `boaz-prod-frontend` PAB | 실제 공개는 아니나 PAB 전체 False | 코드 편입 시 PAB 활성화 여부 (변경이므로 승인 필요) | 결정 대기 |
| `boaz-recruitment` lifecycle | `expire-after-30days` (30일 만료) | 보존 기준 유지 확인 후 코드에 동일하게 반영 | 결정 대기 |
| `boaz-dev-frontend` | 서비스 중인 배포 없음, policy가 이미 삭제된 CloudFront 배포를 참조 | 관리 대상 유지/제외/정리 | 결정 대기 |
| 관리 대상 외 S3 버킷 | `boaz-website`, `boaz-website-dev`, `boazweb`, `survey-da/dv.bigdataboaz.com` 존재 | 각 버킷을 관리 대상/제외로 분류 | 결정 대기 |
| 레거시 OAI·고아 레코드 | 미사용 OAI 4개, 대응 자원 없는 ACM 검증 CNAME(`back`, `cdn`, `server`) | 정리 여부 | 결정 대기 |
| Route53 `dev`/`dev-back` A 레코드 | CloudFront가 아닌 외부 IP 직결 | 관리 대상 포함 여부 | 결정 대기 |
| SSH 접근 방식 | `prod-ssh-sg`가 개인 IP `/32` 2개에 22번 허용. EC2 role에 `AmazonSSMManagedInstanceCore` 있음 | Session Manager로 대체하고 `prod-ssh-sg` 제거할지 | 결정 대기 |
| Network ACL | default NACL 1개만 존재 | `aws_default_network_acl`로 관리할지, 제외할지 | 결정 대기 |
| CloudTrail | 조사하지 않음 | 존재 여부 확인. 없으면 콘솔 변경 추적(관리 이벤트) 활성화 여부 결정 | 조사 필요 |

## 참고

- 미결정 항목이 있는 자원은 추정값으로 import/apply하지 않음.
- state 저장소 방식(S3 native lock vs DynamoDB)은 설계상 S3 native lock(`use_lockfile=true`)으로 확정. 버킷·키 이름만 미결정. 기존 버킷 11개 중 state 후보 버킷은 없음.
- 기존 admin CloudFront 배포는 계획서 인벤토리에 포함된 import 대상이다. 계획서 비목표인 "admin 신규 환경 구성"과는 별개다.
- 조사 근거: `docs/records/inventory.md`, 조사 시점 2026-09-23.
