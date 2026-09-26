# Import 기록 (Import Log)

자원을 Terraform으로 편입(import)할 때 각 자원마다 아래 레코드를 남긴다. 실제 import·apply 단계(후속 작업)에서 채운다. 현재는 양식과 대상 목록만 준비된 상태다.

secret 값·RDS password·복호화된 SSM 값은 어떤 필드에도 기록하지 않는다.

## 레코드 필드 정의

| 필드 | 설명 |
|---|---|
| group | network / iam / params / storage / compute / database / cdn / deploy (`docs/guides/import-procedure.md` 1절과 같음) |
| terraform_address | Terraform 리소스 주소 (예: `module.network.aws_vpc.main`) |
| aws_identifier | 실제 AWS 식별자 (import ID) |
| identifier_source | 확인에 사용한 AWS CLI 명령 + 출력 필드 |
| observed_at_utc | 조사 시점 (UTC) |
| current_configuration_summary | 현재 설정 요약 |
| ownership | managed / data_source / excluded / unconfirmed |
| import_block_commit | import 블록을 추가한 커밋 해시 |
| plan_exit_code_and_summary | `terraform plan` 종료 코드 + 요약 (No changes / create N / update N) |
| remaining_diff | 잔여 diff (없으면 none) |
| destroy_replace_check | pass / blocked (delete·replace 포함 시 blocked) |
| approval_or_recovery_action | 승인·복구 조치 |
| operator | 작업자 |

## 레코드 템플릿

```text
- group:
  terraform_address:
  aws_identifier:
  identifier_source:
  observed_at_utc:
  current_configuration_summary:
  ownership:
  import_block_commit:
  plan_exit_code_and_summary:
  remaining_diff:
  destroy_replace_check:
  approval_or_recovery_action:
  operator:
```

## 그룹별 진행 상태

그룹 import를 시작하는 사람이 상태를 `진행 중`으로 바꾸고 담당자·시작 시각을 적는다. `진행 중`인 그룹은 한 번에 1개만 둔다(apply 순서 규칙, `docs/guides/import-procedure.md` 2절). 실제 식별자는 `docs/records/inventory.md` 참조.

| 순서 | group | 주요 대상 | 담당자 | 시작 시각(KST) | 상태 |
|---|---|---|---|---|---|
| 1 | network | VPC, Subnet 4개, Route Table 3개(+association), IGW, SG 6개와 규칙, prefix list(data_source) | | | 대기 |
| 2 | iam | OIDC provider, role 4개, role별 정책 연결·인라인 정책, EC2 instance profile | | | 대기 |
| 3 | params | `/boaz/infra/*` 12개, 앱 시크릿 존재·타입 확인(값 제외) | | | 대기 |
| 4 | storage | S3 버킷(codedeploy·prod-frontend·frontend-admin·recruitment·archiving) + 버킷별 정책·퍼블릭 차단·암호화·lifecycle | | | 대기 |
| 5 | compute | EC2-A, EC2-B, EIP와 연결, Target Group과 EC2-A 등록(ALB는 `season_capacity = on`일 때만) | | | 대기 |
| 6 | database | RDS(암호화 키 포함), subnet group, parameter group | | | 대기 |
| 7 | cdn | CloudFront api·www·admin(`web_acl_id`·OAC·오류 응답 포함), OAC 2개, Route53 zone·record, ACM(us-east-1) | | | 대기 |
| 8 | deploy | CodeDeploy app, deployment group(`ec2_tag_set` `app=boaz-api`, 자동 롤백) | | | 대기 |

## 관리 제외 / 미확정 (조사 기준)

| 대상 | 분류 | 사유 |
|---|---|---|
| default SG | excluded | VPC 기본 SG |
| NAT Gateway | data_source | 존재하지 않음 (private subnet 외부 경로 없음) |
| CloudFront 관리형 prefix list | data_source | AWS 관리형 |
| RDS option group `default:mysql-8-4` | data_source | AWS 기본 |
| Route53 NS/SOA/TXT/ACM 검증 CNAME | data_source | 도메인 검증·인증서 발급용 |
| S3 `boaz-website`, `boaz-website-dev`, `boazweb`, `survey-da/dv.bigdataboaz.com` | unconfirmed | 관리 대상 여부 미결정 (decisions 참조) |
| Route53 `dev`/`dev-back` A 레코드 | unconfirmed | 관리 대상 여부 미결정 (decisions 참조) |
| S3 `boaz-dev-frontend` | unconfirmed | 서비스 중인 배포 없음, 삭제된 배포 참조 policy (decisions 참조) |
| WAF WebACL 3개 | unconfirmed | 관리 방식 미결정 (decisions 참조) |
| 레거시 OAI 4개, ACM 검증 CNAME `back`/`cdn`/`server` | unconfirmed | 미사용·고아 추정, 정리 여부 미결정 |
| default Network ACL | unconfirmed | 관리 여부 미결정 |

## 참고

- 조사 근거: `docs/records/inventory.md` (조사 시점 2026-09-23, read-only)
- 결정 필요 항목: `docs/records/decisions.md`
- import 블록은 그룹별로 `envs/prod/imports/<group>.tf`에 추가(`docs/guides/import-procedure.md` 1절).
