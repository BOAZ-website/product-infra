# AWS 운영 자원 현황 인벤토리

조사 프로파일: `--profile tf --region ap-northeast-2` (CloudFront/ACM은 `us-east-1`)
조사 계정: `156312218841` (`arn:aws:iam::156312218841:user/admin_daehyun`)
조사 시점(UTC): 2026-09-23
조사 방식: read-only (describe/list/get). secret 값·RDS password·SSM SecureString 복호화 미실행.
현행 상태: `season_mode=off`와 일치 (ALB 없음, EC2-B stopped·`app` 태그 없음, CloudFront api origin EC2-A:8080, RDS Multi-AZ false).

ownership 구분: `managed`(Terraform 관리 대상) / `data`(참조만) / `excluded`(관리 제외) / `unconfirmed`(추가 확인 필요)

## 1. 계정

| 항목 | 값 |
|---|---|
| Account | `156312218841` |
| Caller ARN | `arn:aws:iam::156312218841:user/admin_daehyun` |
| Region | `ap-northeast-2` |

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
| NAT Gateway | 없음 | private subnet은 외부 아웃바운드 경로 없음 | data |

## 3. 보안그룹

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| ALB SG | `sg-0b98cad292282ebe5` | `boaz-alb-sg`, ingress TCP 80 ← prefix list `pl-22a6434b` | managed |
| ALB→EC2 SG | `sg-0a1b971b7c6ecca6b` | `prod-alb-to-ec2-sg`, ingress TCP 8080 ← ALB SG | managed |
| CloudFront→EC2 SG | `sg-0f687731f48f23809` | `prod-cf-to-ec2-sg`, ingress TCP 8080 ← prefix list `pl-22a6434b` | managed |
| RDS SG | `sg-031dfbcef8f27664b` | `prod-rds-sg`, ingress TCP 3306 ← EC2→RDS SG | managed |
| EC2→RDS SG | `sg-0b85c4efb533a1fe4` | `prod-ec2-to-rds-sg`, egress TCP 3306 → RDS SG | managed |
| SSH SG | `sg-05b499bad8d9637d1` | `prod-ssh-sg`, ingress TCP 22 ← `[개인 IP 삭제]/32`, `[개인 IP 삭제]/32` | managed |
| default SG | `sg-07142d09e8f0ba4f1` | VPC default, self-ref | excluded (기본 SG) |
| CloudFront prefix list | `pl-22a6434b` | AWS 관리형 `com.amazonaws.global.cloudfront.origin-facing` | data |

SSH 규칙은 특정 IP `/32` 2개로 제한됨. `0.0.0.0/0` 과도 규칙 아님.

## 4. 컴퓨팅 (EC2)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| EC2-A | `i-08bb34407c19504cf` | `boaz-api-prod-A`, running, t3.small, 2a, subnet `...224a25`, private 10.0.1.44, public [서버 공인 IP 삭제], AMI `ami-0fc2b553b2bbfaee0`, 태그 `app=boaz-api` 있음 | managed |
| EC2-B | `i-05405847d3897364a` | `boaz-api-prod-B`, stopped, t3.small, 2c, subnet `...42563b`, private 10.0.2.35, AMI `ami-071edff9d93c43c82`, 태그 `app` 없음 | managed |
| Instance Profile | `arn:aws:iam::156312218841:instance-profile/role-prod-ec2` | EC2-A/B 공통 | managed |

EC2-A/B는 4개 SG 공유: `prod-ec2-to-rds-sg`, `prod-ssh-sg`, `prod-cf-to-ec2-sg`, `prod-alb-to-ec2-sg`.
EC2-B 실제 ID는 `i-05405847d3897364a` (계획서 참조값 `i-05405847d3897364`와 끝자리 `a` 차이, 실측값이 정확).
EC2-A/B AMI가 서로 다름. drift 위험은 서버 코드 편입 시 확인 필요.

## 5. 데이터베이스 (RDS)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| RDS instance | `boaz-prod-db` | MySQL 8.4.11, db.t3.micro, gp3 20GB, Multi-AZ false, 비공개, deletion_protection true, available | managed |
| DB Subnet Group | `boaz-prod-rds-subnet-group` | VPC `...3cf40`, private subnet 2c/2a | managed |
| DB Parameter Group | `boaz-prod-mysql84` | RDS 연결 | managed |
| RDS SG | `sg-031dfbcef8f27664b` | (보안그룹 참조) | managed |

password는 조회하지 않음. Terraform 값 관리 대상 아님.

## 6. 로드밸런싱

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Target Group | `arn:aws:elasticloadbalancing:ap-northeast-2:156312218841:targetgroup/boaz-api-tg/d42747d4f4ff49e6` | `boaz-api-tg`, HTTP 8080, HC `/actuator/health`, target type instance | managed |
| ALB | 없음 | season_mode=on에서만 생성 | managed (조건부) |

## 7. CDN (CloudFront)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| CloudFront api | `E2SER81QYNPRO9` | alias `api.bigdataboaz.com`, origin 1개 → EC2-A DNS:8080, http-only, Deployed | managed |
| CloudFront www | `EAK2LBIAYWPBV` | alias `www.bigdataboaz.com`, origin 1개 → `boaz-prod-frontend` S3, Deployed | managed |
| CloudFront admin | `E2GM63NBDWPND0` | alias `admin.bigdataboaz.com`, origin 1개 → `boaz-prod-frontend-admin` S3, Deployed | managed |

세 배포 모두 viewer cert `arn:aws:acm:us-east-1:156312218841:certificate/1f7185b8-b897-4fb2-b7f9-eccc7b23a80b` 공유.
계획서의 `dev` CloudFront는 실측에 없음. 대신 `admin` 배포 존재. (계획서와 차이 → decisions 기록)

## 8. DNS (Route53)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Hosted Zone | `Z06161783647LR0PZWA47` | `bigdataboaz.com.`, public, 레코드 15개 | managed |
| A(alias) `api` | - | `api.bigdataboaz.com` → `dsa1wlpkbaoop.cloudfront.net` | managed |
| A(alias) `www` | - | `www.bigdataboaz.com` → `d3dli2v91bzf4q.cloudfront.net` | managed |
| A(alias) `admin` | - | `admin.bigdataboaz.com` → `d1twazwh9pa6be.cloudfront.net` | managed |
| A `dev` | - | `dev.bigdataboaz.com` → `3.39.31.209` (직결) | unconfirmed (대상 여부) |
| A `dev-back` | - | `dev-back.bigdataboaz.com` → `210.205.132.46` (직결) | unconfirmed (대상 여부) |
| NS/SOA/TXT/ACM 검증 CNAME | - | 도메인 검증·인증서 발급용 | data |

## 9. 인증서 (ACM)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| ACM certificate | `arn:aws:acm:us-east-1:156312218841:certificate/1f7185b8-b897-4fb2-b7f9-eccc7b23a80b` | `*.bigdataboaz.com` wildcard, ISSUED, AMAZON_ISSUED, CloudFront 3개 사용 중, region `us-east-1` | managed |

## 10. 배포 (CodeDeploy)

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| CodeDeploy App | `boaz-backend` | - | managed |
| Deployment Group | `codedeploy-prod` | config `CodeDeployDefault.AllAtOnce`, IN_PLACE, WITHOUT_TRAFFIC_CONTROL, service role `role-prod-codedeploy` | managed |
| Service Role | `arn:aws:iam::156312218841:role/role-prod-codedeploy` | - | managed |

배포 그룹 EC2 태그 필터가 실측상 비어있음(`ec2TagFilters: null`). 계획서의 `app=boaz-api` 태그 타겟과 차이 → decisions 기록.

## 11. IAM

| 자원 | 식별자 | 현재 설정 | ownership |
|---|---|---|---|
| Role backend deploy | `arn:aws:iam::156312218841:role/role-prod-github-actions` | - | managed |
| Role frontend deploy | `arn:aws:iam::156312218841:role/role-prod-github-actions-frontend` | - | managed |
| Role CodeDeploy | `arn:aws:iam::156312218841:role/role-prod-codedeploy` | - | managed |
| Role EC2 | `arn:aws:iam::156312218841:role/role-prod-ec2` | instance profile 연결 | managed |
| GitHub OIDC provider | `arn:aws:iam::156312218841:oidc-provider/token.actions.githubusercontent.com` | - | managed |

## 12. 파라미터 (SSM)

`/boaz/infra/*` 정확히 12개 (값 미조회, 이름·type·KMS만):

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

앱 secret 파라미터(값·type 미관리 대상, 이름만 확인): `DB_PASSWORD`, `DB_URL`, `DB_USERNAME`, `JWT_SECRET`, `GOOGLE_CLIENT_ID/SECRET`, `KAKAO_CLIENT_ID/SECRET`, `NAVER_CLIENT_ID/SECRET`, `SWAGGER_USER/PASSWORD`, `S3_ARCHIVING_BUCKET_NAME`, `S3_RECRUITMENT_BUCKET_NAME`. 루트 네임스페이스(`/boaz/app/*` 아님)에 위치. SecureString 아님(String) → decisions 기록.

## 13. 스토리지 (S3)

| 버킷 | region | versioning | 암호화 | PublicAccessBlock | ownership |
|---|---|---|---|---|---|
| `boaz-codedeploy-bucket` | ap-northeast-2 | None | AES256 | 전체 True | managed |
| `boaz-prod-frontend` | ap-northeast-2 | None | AES256 | 전체 False | managed |
| `boaz-prod-frontend-admin` | ap-northeast-2 | None | AES256 | 전체 True | managed |
| `boaz-dev-frontend` | ap-northeast-2 | None | AES256 | 전체 True | managed |
| `boaz-recruitment` | ap-northeast-2 | None | AES256 | 전체 True | managed |
| `boaz-archiving` | ap-northeast-2 | None | AES256 | 전체 False | managed |
| `boaz-website` | ap-northeast-2 | None | AES256 | 전체 False | unconfirmed (대상 여부) |
| `boaz-website-dev` | ap-northeast-2 | None | AES256 | 미설정 | unconfirmed (대상 여부) |
| `boazweb` | ap-northeast-2 | Enabled | AES256 | 전체 False | unconfirmed (대상 여부) |
| `survey-da.bigdataboaz.com` | ap-northeast-2 | None | AES256 | 전체 True | unconfirmed (대상 여부) |
| `survey-dv.bigdataboaz.com` | ap-northeast-2 | None | AES256 | 전체 True | unconfirmed (대상 여부) |

policy·lifecycle 상세는 storage 코드 편입 시 추가 조사.

## 계획서와의 차이 (요약)

| 항목 | 계획서 | 실측 | 처리 |
|---|---|---|---|
| EC2-B ID | `i-05405847d3897364` | `i-05405847d3897364a` | 실측값 사용 |
| 3번째 CloudFront | `dev` | `admin` | 실측 반영 |
| SSH SG | 명시 없음 | `prod-ssh-sg` 존재 (IP /32 2개) | 인벤토리 반영 |
| CodeDeploy 태그 타겟 | `app=boaz-api` | DG 태그 필터 비어있음 | decisions 기록 |
| 앱 secret 저장 방식 | (SecureString 검토) | String 타입 | decisions 기록 |
| 관리 대상 외 버킷 | 명시 없음 | `boaz-website`, `boazweb`, `survey-*` 등 | unconfirmed 기록 |
