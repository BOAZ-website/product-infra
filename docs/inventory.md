# AWS 운영 자원 현황 인벤토리

조사 프로파일: `--profile tf --region ap-northeast-2` (CloudFront/ACM/WAF는 `us-east-1`)
조사 계정: `156312218841` (조사자 IAM 사용자명은 공개 저장소이므로 기재하지 않음)
조사 시점(UTC): 2026-09-23
조사 방식: read-only (describe/list/get). secret 값·RDS password·SSM SecureString 복호화 미실행.
현행 상태: `season_mode=off`와 일치 (ALB·listener 없음, EC2-B stopped·`app` 태그 없음, Target Group 등록 대상은 EC2-A뿐, CloudFront api origin EC2-A:8080, RDS Multi-AZ false).

ownership 구분: `managed`(Terraform 관리 대상) / `data_source`(참조만) / `excluded`(관리 제외) / `unconfirmed`(추가 확인 필요)

공개 저장소이므로 개인 IP·개인 계정명은 기재하지 않는다. 필요하면 AWS에서 직접 조회한다.

## 1. 계정

| 항목 | 값 |
|---|---|
| Account | `156312218841` |
| Region | `ap-northeast-2` |
| 계정 수준 S3 PublicAccessBlock | 미설정 |

## 2. 네트워크

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| VPC | `vpc-0767ac83c72b3cf40` | `boaz-prod-vpc`, `10.0.0.0/16`, 비default | managed |
| Public Subnet 2a | `subnet-092734d1357224a25` | `boaz-public-a`, `10.0.1.0/24`, MapPublicIp=true | managed |
| Public Subnet 2c | `subnet-02fd34391da42563b` | `boaz-public-c`, `10.0.2.0/24`, MapPublicIp=true | managed |
| Private Subnet 2a | `subnet-000d98c349b771ee1` | `boaz-private-a`, `10.0.11.0/24`, MapPublicIp=false | managed |
| Private Subnet 2c | `subnet-04cc7bdb725c4f5a6` | `boaz-private-c`, `10.0.12.0/24`, MapPublicIp=false | managed |
| Route Table (main) | `rtb-062f6a4eb965b312e` | main, local 라우트만 | managed |
| Route Table (public) | `rtb-09c3c941b458da9fb` | public subnet 2개 연결, `0.0.0.0/0`→IGW | managed |
| Route Table (private) | `rtb-02a4df14844468ea8` | private subnet 2개 연결, local만 (NAT 없음) | managed |
| Internet Gateway | `igw-0c71eb6adda55dbaf` | VPC attached, available | managed |
| Network ACL | `acl-07ffd275e736d47f0` | default NACL 1개, subnet 4개 연결, 사용자 정의 NACL 없음 | unconfirmed (`aws_default_network_acl` 관리 여부) |
| NAT Gateway | 없음 | private subnet은 외부 아웃바운드 경로 없음 | data_source |

## 3. 보안그룹

모든 규칙은 SG 인라인 규칙이다. 코드 편입 시 인라인 규칙과 별도 rule 리소스를 섞지 않는다.

| 자원 | 식별자 | ingress | egress | ownership |
|---|---|---|---|---|
| ALB SG | `sg-0b98cad292282ebe5` | `boaz-alb-sg`, TCP 80 ← prefix list `pl-22a6434b` | all → `0.0.0.0/0` | managed |
| ALB→EC2 SG | `sg-0a1b971b7c6ecca6b` | `prod-alb-to-ec2-sg`, TCP 8080 ← ALB SG | all → `0.0.0.0/0` | managed |
| CloudFront→EC2 SG | `sg-0f687731f48f23809` | `prod-cf-to-ec2-sg`, TCP 8080 ← prefix list `pl-22a6434b` | all → `0.0.0.0/0` | managed |
| RDS SG | `sg-031dfbcef8f27664b` | `prod-rds-sg`, TCP 3306 ← EC2→RDS SG | all → `0.0.0.0/0` | managed |
| EC2→RDS SG | `sg-0b85c4efb533a1fe4` | `prod-ec2-to-rds-sg`, 없음 | TCP 3306 → RDS SG만 (기본 egress 제거됨) | managed |
| SSH SG | `sg-05b499bad8d9637d1` | `prod-ssh-sg`, TCP 22 ← 개인 IP `/32` 2개 | all → `0.0.0.0/0` | managed |
| default SG | `sg-07142d09e8f0ba4f1` | VPC default, self-ref | all → `0.0.0.0/0` | excluded (기본 SG) |
| CloudFront prefix list | `pl-22a6434b` | AWS 관리형 `com.amazonaws.global.cloudfront.origin-facing` | - | data_source |

- 기본 egress(`all → 0.0.0.0/0`)도 코드에 명시해야 한다. 명시하지 않으면 plan이 egress 삭제를 제안할 수 있다.
- SSH ingress는 `/32` 2개로 제한되어 있다. EC2 role에 `AmazonSSMManagedInstanceCore`가 있으므로 Session Manager 대체 여부를 decisions에 기록했다.

## 4. 컴퓨팅 (EC2)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| EC2-A | `i-08bb34407c19504cf` | `boaz-api-prod-A`, running, t3.small, 2a, subnet `...224a25`, private 10.0.1.44, AMI `ami-0fc2b553b2bbfaee0`, 태그 `app=boaz-api` 있음, key pair `boaz_codedeploy`, IMDSv2 required, root volume `vol-011d957b0eda19d75` | managed |
| EC2-B | `i-05405847d3897364a` | `boaz-api-prod-B`, stopped, t3.small, 2c, subnet `...42563b`, private 10.0.2.35, AMI `ami-071edff9d93c43c82`, 태그 `app` 없음, key pair `boaz_codedeploy`, IMDSv2 required, root volume `vol-0ac810fb890bf0c4d` | managed |
| Elastic IP (EC2-A) | `eipalloc-0d58d66169c7560bb` | `15.165.102.5`, association `eipassoc-0549083bd71126507` → EC2-A | managed |
| Instance Profile | `arn:aws:iam::156312218841:instance-profile/role-prod-ec2` | EC2-A/B 공통 | managed |
| Launch Template / ASG | 없음 | 조회 결과 0개 | - |

- EC2-A/B는 4개 SG를 공유한다: `prod-ec2-to-rds-sg`, `prod-ssh-sg`, `prod-cf-to-ec2-sg`, `prod-alb-to-ec2-sg`.
- EC2-A에는 EIP가 연결되어 있다. api CloudFront origin `ec2-15-165-102-5...compute.amazonaws.com`은 EIP에서 파생된 DNS이므로 stop/start 후에도 바뀌지 않는다.
- EC2-A/B의 AMI가 서로 다르다. drift 여부는 compute 코드 편입 시 확인한다.

## 5. 데이터베이스 (RDS)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| RDS instance | `boaz-prod-db` | MySQL 8.4.11, db.t3.micro, AZ 2a, Multi-AZ false, 비공개, deletion_protection true, available | managed |
| 스토리지 | - | gp3 20GB, iops 3000, throughput 125, max_allocated_storage 100, 암호화 true, KMS `arn:aws:kms:ap-northeast-2:156312218841:key/0274f4c7-b58a-4721-b0b0-6571745a562c` | managed |
| 백업·유지보수 | - | backup retention 7일, backup window `19:00-19:30`, maintenance window `thu:20:00-thu:20:30`, copy_tags_to_snapshot true, auto minor upgrade true | managed |
| 기타 | - | CloudWatch log export `error`, CA `rds-ca-rsa2048-g1` | managed |
| DB Subnet Group | `boaz-prod-rds-subnet-group` | VPC `...3cf40`, private subnet 2c/2a | managed |
| DB Parameter Group | `boaz-prod-mysql84` | RDS 연결 | managed |
| Option Group | `default:mysql-8-4` | AWS 기본 | data_source |
| RDS SG | `sg-031dfbcef8f27664b` | (보안그룹 참조) | managed |

- `storage_encrypted`와 `kms_key_id`는 코드 값이 다르면 replace를 유발한다. 위 값을 그대로 코드에 적는다.
- password는 조회하지 않았으며, Terraform에서 값을 관리하지 않는다.

## 6. 로드밸런싱

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Target Group | `arn:aws:elasticloadbalancing:ap-northeast-2:156312218841:targetgroup/boaz-api-tg/d42747d4f4ff49e6` | `boaz-api-tg`, HTTP 8080, HC `/actuator/health`, target type instance | managed |
| TG 등록 대상 | `i-08bb34407c19504cf:8080` | EC2-A만 등록, 상태 `unused` (LB 없음) | managed (`aws_lb_target_group_attachment`) |
| ALB / Listener | 없음 | season_mode=on에서만 생성 | managed (조건부) |

## 7. CDN (CloudFront)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| CloudFront api | `E2SER81QYNPRO9` | alias `api.bigdataboaz.com`, origin 1개 → EC2-A DNS:8080, http-only, viewer redirect-to-https, cache policy CachingDisabled `4135ea2d-6df8-44a3-9df3-4b5a84be39ad`, origin request policy AllViewer `216adef6-5c7f-47e4-b989-5492eafa07d3`, custom error 6개(403/404/500/502/503/504, 응답 페이지 없이 오류 캐싱 설정만) | managed |
| CloudFront www | `EAK2LBIAYWPBV` | alias `www.bigdataboaz.com`, origin → `boaz-prod-frontend` S3, OAC `E1FNQ7TE1SQXLA`, default root `index.html`, cache policy CachingOptimized `658327ea-f89d-4fab-a63d-7e88639e58f6`, custom error 403/404 → 200 `/index.html` (SPA 라우팅) | managed |
| CloudFront admin | `E2GM63NBDWPND0` | alias `admin.bigdataboaz.com`, origin → `boaz-prod-frontend-admin` S3, OAC `E12ZM8KVUOM9GD`, default root `index.html`, cache policy CachingOptimized, custom error 없음 | managed |
| WAF WebACL (api) | `CreatedByCloudFront-930c5257` (`f0d71842-100a-4ab8-83cf-9f2dfce907b9`) | us-east-1, CloudFront 콘솔 생성 | unconfirmed (관리 방식) |
| WAF WebACL (www) | `CreatedByCloudFront-5c92f680` (`9cd516fe-bcbd-4aae-ba62-b72814b0d3bc`) | us-east-1, CloudFront 콘솔 생성 | unconfirmed (관리 방식) |
| WAF WebACL (admin) | `CreatedByCloudFront-7ae4f702` (`d6dbf300-fce0-4da7-b428-10e20148cd41`) | us-east-1, CloudFront 콘솔 생성 | unconfirmed (관리 방식) |
| 레거시 OAI | `E26A1E75IVQXNC`, `E94HALX0MGFFC`, `E17AB8M3IVDOMU`, `E1LMKYP1IJ04II` | 현재 배포 3개 중 사용하는 곳 없음 | unconfirmed (정리 대상) |

- 세 배포 공통: viewer cert `arn:aws:acm:us-east-1:156312218841:certificate/1f7185b8-b897-4fb2-b7f9-eccc7b23a80b`, `TLSv1.2_2021`, `PriceClass_All`, 로깅 꺼짐.
- 배포 코드에 `web_acl_id`를 적지 않으면 plan이 WAF 연결을 해제한다. 보안 설정이 약해지므로 반드시 WebACL ARN을 명시한다.
- 세 번째 배포가 admin인 것은 계획서(`terraform-migration-plan.md`, `infra-spec.md`)와 일치한다. `dev` 배포는 티켓 문구에만 있었다.

## 8. DNS (Route53)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Hosted Zone | `Z06161783647LR0PZWA47` | `bigdataboaz.com.`, public, 레코드 15개 | managed |
| A(alias) `api` | - | `api.bigdataboaz.com` → `dsa1wlpkbaoop.cloudfront.net` | managed |
| A(alias) `www` | - | `www.bigdataboaz.com` → `d3dli2v91bzf4q.cloudfront.net` | managed |
| A(alias) `admin` | - | `admin.bigdataboaz.com` → `d1twazwh9pa6be.cloudfront.net` | managed |
| A `dev` | - | `dev.bigdataboaz.com` → 외부 IP 직결 (값 비기재) | unconfirmed (대상 여부) |
| A `dev-back` | - | `dev-back.bigdataboaz.com` → 외부 IP 직결 (값 비기재) | unconfirmed (대상 여부) |
| ACM 검증 CNAME (`www`, apex, `dev`, `dev-back`) | - | 인증서 발급·갱신용 | data_source |
| ACM 검증 CNAME (`back`, `cdn`, `server`) | - | 대응하는 A 레코드·인증서 없음 | unconfirmed (고아 레코드 추정) |
| NS/SOA/TXT | - | 위임·도메인 검증용 | data_source |

## 9. 인증서 (ACM)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| ACM certificate | `arn:aws:acm:us-east-1:156312218841:certificate/1f7185b8-b897-4fb2-b7f9-eccc7b23a80b` | `*.bigdataboaz.com` wildcard, ISSUED, AMAZON_ISSUED, CloudFront 3개 사용 중, region `us-east-1` | managed |

ap-northeast-2에는 인증서가 없다.

## 10. 배포 (CodeDeploy)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| CodeDeploy App | `boaz-backend` | - | managed |
| Deployment Group | `codedeploy-prod` | config `CodeDeployDefault.AllAtOnce`, IN_PLACE, WITHOUT_TRAFFIC_CONTROL, service role `role-prod-codedeploy`, 대상 `ec2TagSet` = `app=boaz-api` (KEY_AND_VALUE), auto rollback enabled (DEPLOYMENT_FAILURE) | managed |
| Service Role | `arn:aws:iam::156312218841:role/role-prod-codedeploy` | - | managed |

- 대상 지정은 `ec2TagFilters`(null)가 아니라 `ec2TagSet`에 설정되어 있으며, 계획서의 `app=boaz-api` 태그 타겟과 일치한다.
- deploy 모듈은 `ec2_tag_filter`가 아니라 `ec2_tag_set` 블록으로 작성해야 plan diff가 생기지 않는다.

## 11. IAM

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Role backend deploy | `arn:aws:iam::156312218841:role/role-prod-github-actions` | - | managed |
| Role frontend deploy | `arn:aws:iam::156312218841:role/role-prod-github-actions-frontend` | - | managed |
| Role CodeDeploy | `arn:aws:iam::156312218841:role/role-prod-codedeploy` | - | managed |
| Role EC2 | `arn:aws:iam::156312218841:role/role-prod-ec2` | instance profile 연결. 관리형 정책 5개(`AmazonS3ReadOnlyAccess`, `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`, `boaz-ec2-s3-archiving-policy`, `boaz-ec2-s3-recruitment-policy`), 인라인 정책 3개(`boaz-codedeploy-read`, `boaz-ssm-read`, `cloudwatch-list-metric`) | managed |
| GitHub OIDC provider | `arn:aws:iam::156312218841:oidc-provider/token.actions.githubusercontent.com` | - | managed |

- role만 import하면 정책 연결은 관리되지 않는다. policy attachment와 인라인 정책도 import 대상에 포함한다.
- `AmazonS3ReadOnlyAccess`는 전체 버킷 읽기 권한이다. 버킷별 정책이 이미 있으므로 과권한 여부를 검토한다.

## 12. 파라미터 (SSM)

`/boaz/infra/*`는 12개다 (값 미조회, 이름·type·KMS만). `describe-parameters`의 결과가 페이지로 나뉘어 반환되므로(10개 + 2개) 개수는 전체 페이지를 합산해 확인했다.

| 이름 | Type | KMS |
|---|---|---|
| `/boaz/infra/ALB_SG_ID` | String | 없음 |
| `/boaz/infra/ALB_SUBNETS` | String | 없음 |
| `/boaz/infra/ALB_PORT` | String | 없음 |
| `/boaz/infra/CLOUDFRONT_DIST_ID` | String | 없음 |
| `/boaz/infra/CODEDEPLOY_APP` | String | 없음 |
| `/boaz/infra/CODEDEPLOY_GROUP` | String | 없음 |
| `/boaz/infra/EC2_A_DOMAIN` | String | 없음 |
| `/boaz/infra/EC2_A_PORT` | String | 없음 |
| `/boaz/infra/EC2_B_ID` | String | 없음 |
| `/boaz/infra/RDS_IDENTIFIER` | String | 없음 |
| `/boaz/infra/TARGET_GROUP_ARN` | String | 없음 |
| `/boaz/infra/S3_BUCKET` | String | 없음 |

앱 파라미터 14개는 루트 네임스페이스(`/boaz/app/*` 아님)에 있다. Terraform에서 값을 관리하지 않는다.

| Type | 이름 | KMS |
|---|---|---|
| SecureString | `DB_PASSWORD`, `JWT_SECRET`, `GOOGLE_CLIENT_SECRET`, `KAKAO_CLIENT_SECRET`, `NAVER_CLIENT_SECRET`, `SWAGGER_PASSWORD` | `alias/aws/ssm` |
| String | `DB_URL`, `DB_USERNAME`, `GOOGLE_CLIENT_ID`, `KAKAO_CLIENT_ID`, `NAVER_CLIENT_ID`, `SWAGGER_USER`, `S3_ARCHIVING_BUCKET_NAME`, `S3_RECRUITMENT_BUCKET_NAME` | 없음 |

## 13. 스토리지 (S3)

| 버킷 | versioning | 암호화 | PublicAccessBlock | 실제 공개 여부(PolicyStatus) | policy·lifecycle | ownership |
|---|---|---|---|---|---|---|
| `boaz-codedeploy-bucket` | None | AES256 | 전체 True | 비공개 | - | managed |
| `boaz-prod-frontend` | None | AES256 | 전체 False | 비공개 (OAC 전용 policy) | OAC policy | managed |
| `boaz-prod-frontend-admin` | None | AES256 | 전체 True | 비공개 | OAC policy | managed |
| `boaz-dev-frontend` | None | AES256 | 전체 True | 비공개 | policy가 존재하지 않는 배포 `E35Q1HDBWZRJF5`를 SourceArn으로 지정 | unconfirmed (서비스 중인 배포 없음) |
| `boaz-recruitment` | None | AES256 | 전체 True | 비공개 | lifecycle `expire-after-30days` (Enabled, 30일 만료) | managed |
| `boaz-archiving` | None | AES256 | 전체 False | **공개** (`Principal:*` `s3:GetObject`) | 공개 읽기 policy | managed |
| `boaz-website` | None | AES256 | 전체 False | 비공개 | 레거시 OAI policy, website hosting 켜짐 | unconfirmed (대상 여부) |
| `boaz-website-dev` | None | AES256 | 미설정 | - | 레거시 OAI policy, website hosting 켜짐 | unconfirmed (대상 여부) |
| `boazweb` | Enabled | AES256 | 전체 False | **공개** | 공개 읽기 policy, CORS `*`, ownership controls 없음(ACL 활성) | unconfirmed (대상 여부) |
| `survey-da.bigdataboaz.com` | None | AES256 | 전체 True | - | - | unconfirmed (대상 여부) |
| `survey-dv.bigdataboaz.com` | None | AES256 | 전체 True | - | - | unconfirmed (대상 여부) |

- 모든 버킷은 `ap-northeast-2`에 있다.
- `boaz-recruitment`의 lifecycle을 코드에 적지 않으면 삭제되어 데이터 보존 동작이 바뀐다.
- `boaz-prod-frontend`는 실제로 공개되어 있지 않지만 PAB가 꺼져 있어 방어 계층이 하나 빠져 있다. admin 버킷과 같이 PAB를 켜는 것을 권고한다(변경이므로 승인 필요).
- 기존 Terraform state 후보 버킷은 11개 버킷 중에 없다.

## 계획서와의 차이 (요약)

| 항목 | 계획서 | 실측 | 처리 |
|---|---|---|---|
| EC2-A EIP | `infra-spec.md` §14: "EIP 미적용" | EIP `eipalloc-0d58d66169c7560bb` 연결됨 | `infra-spec.md` 수정, EIP import 대상 추가 |
| EC2-B ID | 계획서는 `i-05405847d3897364a`로 일치 | `i-05405847d3897364a` | `design.md` 사전 인벤토리 표의 잘린 값만 오타 → 수정 |
| 3번째 CloudFront | 계획서는 admin `E2GM63NBDWPND0`로 일치 | admin | 차이 없음 (티켓 문구의 `dev`만 다름) |
| CodeDeploy 태그 타겟 | `app=boaz-api` | `ec2TagSet` = `app=boaz-api` | 차이 없음 |
| 앱 secret 저장 방식 | (SecureString 검토) | secret 6개는 이미 SecureString | 차이 없음, decisions 항목 재작성 |
| CloudFront WAF | 명시 없음 | 3개 배포 모두 WebACL 연결 | decisions 기록 |
| 공개 S3 버킷 | 명시 없음 | `boaz-archiving`, `boazweb` 공개 읽기 | decisions 기록 |
| 관리 대상 외 버킷·레코드·OAI | 명시 없음 | `boaz-website*`, `boazweb`, `survey-*`, 레거시 OAI 4개, 고아 ACM CNAME 3개 | unconfirmed 기록 |
