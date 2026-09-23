# 결정 필요 항목 및 승인 게이트

미결정 항목과 그 결정 전까지 진행 불가한 작업을 기록. 각 항목은 결정되기 전까지 연관 자원의 코드 편입(import)·apply를 차단.

상태 표기: `결정 대기` / `결정 완료`

## 미결정 항목

| 항목 | 상태 | 결정 필요 주체 | 필요 시점 | 차단되는 작업 |
|---|---|---|---|---|
| Terraform state 저장소 버킷·키 | 결정 대기 | [확인 필요] | 상태 저장소 구성 착수 전 | bootstrap, envs/prod backend 초기화 |
| EC2-A 고정 IP(Elastic IP) 도입 여부 | 결정 대기 | [확인 필요] | 서버 코드 편입 전 | compute 모듈, CloudFront origin 안정성 |
| EC2-B 시작·중지 제어 방식 (`aws_ec2_instance_state` vs ASG) | 결정 대기 | [확인 필요] | 서버 코드 편입 전 | compute 모듈, season_mode 전환 |
| 앱 secret SecureString 전환 여부·시점 | 결정 대기 | [확인 필요] | 파라미터 코드 편입 전 | params 모듈 |
| 코드 반영(apply) 승인자 지정 (GitHub Environment reviewer) | 결정 대기 | [확인 필요] | apply workflow 활성화 전 | terraform-apply workflow |

## 조사에서 확인된 계획서 대비 차이 (결정 필요)

| 항목 | 조사 결과 | 결정 필요 내용 | 상태 |
|---|---|---|---|
| 3번째 CloudFront 배포 | `admin.bigdataboaz.com` (`E2GM63NBDWPND0`) 존재, `dev` CloudFront 없음 | admin 배포를 이번 범위에 포함할지, 계획서 비목표(admin 신규 환경)와 관계 정리 | 결정 대기 |
| CodeDeploy 배포 그룹 태그 필터 | `codedeploy-prod`의 `ec2TagFilters`가 비어있음 | 태그 기반 타겟이 아닌 실제 타겟 지정 방식 확인 후 deploy 모듈 반영 방식 결정 | 결정 대기 |
| 앱 secret 저장 타입 | `DB_PASSWORD`, `JWT_SECRET` 등이 `String` 타입 (SecureString 아님) | SecureString 전환 여부·시점 (위 미결정 항목과 연동) | 결정 대기 |
| 관리 대상 외 S3 버킷 | `boaz-website`, `boaz-website-dev`, `boazweb`, `survey-da/dv.bigdataboaz.com` 존재 | 각 버킷을 관리 대상/제외로 분류 | 결정 대기 |
| Route53 `dev`/`dev-back` A 레코드 | CloudFront 아닌 IP 직결 (`3.39.31.209`, `210.205.132.46`) | 관리 대상 포함 여부 결정 | 결정 대기 |

## 참고

- 미결정 항목이 있는 자원은 추정값으로 import/apply하지 않음.
- state 저장소 방식(S3 native lock vs DynamoDB)은 설계상 S3 native lock(`use_lockfile=true`)으로 확정. 버킷·키 이름만 미결정.
- 조사 근거: `docs/inventory.md`, 조사 시점 2026-09-23.
