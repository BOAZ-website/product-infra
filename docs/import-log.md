# Import 기록 (Import Log)

자원을 Terraform으로 편입(import)할 때 각 자원마다 아래 레코드를 남긴다. 실제 import·apply 단계(후속 작업)에서 채운다. 현재는 양식과 대상 목록만 준비된 상태다.

secret 값·RDS password·복호화된 SSM 값은 어떤 필드에도 기록하지 않는다.

## 레코드 필드 정의

| 필드 | 설명 |
|---|---|
| group | network / iam-params / storage / compute / database / alb-target / cdn-route53-acm / deploy |
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

## Import 대상 목록 (조사 기준, 미착수)

표준 import 순서. 실제 식별자는 `docs/inventory.md` 참조.

| 순서 | group | 주요 대상 | 상태 |
|---|---|---|---|
| 1 | network | VPC, Subnet 4개, Route Table 3개(+association), IGW, SG 6개(인라인 ingress·egress 포함), prefix list(data_source) | 미착수 |
| 2 | iam-params | OIDC provider, role 4개, role별 policy attachment·인라인 정책, `/boaz/infra/*` 12개 | 미착수 |
| 3 | storage | S3 버킷 (codedeploy/prod-frontend/frontend-admin/recruitment/archiving) + 버킷별 policy·PAB·암호화·lifecycle(`boaz-recruitment`) | 미착수 |
| 4 | compute | EC2-A `i-08bb34407c19504cf`, EC2-B `i-05405847d3897364a`, EIP `eipalloc-0d58d66169c7560bb`·association `eipassoc-0549083bd71126507`, instance profile | 미착수 |
| 5 | database | RDS `boaz-prod-db`(암호화 KMS 키 포함), subnet group, parameter group | 미착수 |
| 6 | alb-target | Target Group `boaz-api-tg`, target attachment(EC2-A:8080) (ALB는 season_mode=on 조건부) | 미착수 |
| 7 | cdn-route53-acm | CloudFront api/www/admin(`web_acl_id`·OAC·custom error 포함), OAC 2개, Route53 zone/record, ACM(us-east-1) | 미착수 |
| 8 | deploy | CodeDeploy app `boaz-backend`, group `codedeploy-prod`(`ec2_tag_set` `app=boaz-api`, auto rollback) | 미착수 |

## 관리 제외 / 미확정 (조사 기준)

| 대상 | 분류 | 사유 |
|---|---|---|
| default SG `sg-07142d09e8f0ba4f1` | excluded | VPC 기본 SG |
| NAT Gateway | data_source | 존재하지 않음 (private subnet 외부 경로 없음) |
| CloudFront prefix list `pl-22a6434b` | data_source | AWS 관리형 |
| RDS option group `default:mysql-8-4` | data_source | AWS 기본 |
| Route53 NS/SOA/TXT/ACM 검증 CNAME | data_source | 도메인 검증·인증서 발급용 |
| S3 `boaz-website`, `boaz-website-dev`, `boazweb`, `survey-da/dv.bigdataboaz.com` | unconfirmed | 관리 대상 여부 미결정 (decisions 참조) |
| Route53 `dev`/`dev-back` A 레코드 | unconfirmed | 관리 대상 여부 미결정 (decisions 참조) |
| S3 `boaz-dev-frontend` | unconfirmed | 서비스 중인 배포 없음, 삭제된 배포 참조 policy (decisions 참조) |
| WAF WebACL 3개 | unconfirmed | 관리 방식 미결정 (decisions 참조) |
| 레거시 OAI 4개, ACM 검증 CNAME `back`/`cdn`/`server` | unconfirmed | 미사용·고아 추정, 정리 여부 미결정 |
| default Network ACL `acl-07ffd275e736d47f0` | unconfirmed | 관리 여부 미결정 |

## 참고

- 조사 근거: `docs/inventory.md` (조사 시점 2026-09-23, read-only)
- 결정 필요 항목: `docs/decisions.md`
- import 블록은 후속 작업에서 `envs/prod/imports.tf`에 추가.
