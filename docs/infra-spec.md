# BOAZ 현행 인프라 SPEC

BOAZ 홈페이지(`www.bigdataboaz.com`)와 API 서버(`api.bigdataboaz.com`)의 **현재 AWS 인프라 구성을 사실 그대로 기술**한 문서다.

- 성격: 현행 상태(as-is) 기술. "지금 무엇이 어떻게 구성되어 있는가"만 담는다.
- 값 기준: AWS read-only 실측 (`--profile product-readonly --region ap-northeast-2`)
- "어떻게 Terraform으로 옮길지"는 이 문서 범위가 아니다 → [`terraform-migration-plan.md`](./terraform-migration-plan.md), [`../.kiro/specs/product-infra-migration/requirements.md`](../.kiro/specs/product-infra-migration/requirements.md) 참조
- 이번 마이그레이션은 lift-and-codify이므로, 인프라 구성 자체는 마이그레이션 전후가 동일하다. 즉 이 문서는 마이그레이션과 무관하게 유효한 현행 인프라의 source of truth다.

---

## 1. 공통

| 항목 | 값 |
|---|---|
| AWS 계정 | `156312218841` |
| 리전 | `ap-northeast-2` (서울) |
| 운영 도메인 | `bigdataboaz.com` (`www`, `api`, `admin`) |
| IaC | 없음 (콘솔 + bash 스크립트로 운영) |

---

## 2. 트래픽 경로

```text
평시:
  사용자 → Route53 → CloudFront(api, E2SER81QYNPRO9) → EC2-A:8080 → RDS(Single-AZ)
  사용자 → Route53 → CloudFront(www)   → S3(boaz-prod-frontend)
  사용자 → Route53 → CloudFront(admin) → S3(boaz-prod-frontend-admin)

시즌중(모집 기간):
  사용자 → Route53 → CloudFront(api) → ALB:80 → EC2-A/EC2-B:8080 → RDS(Multi-AZ)
```

- api CloudFront origin은 현재 **EC2-A 퍼블릭 DNS에 직접 연결**되어 있다 (`ec2-15-165-102-5.ap-northeast-2.compute.amazonaws.com`, port 8080).
- 시즌에는 origin이 ALB DNS(port 80)로 교체된다.

---

## 3. 네트워크

### VPC / Subnet

| 리소스 | 식별자 | 비고 |
|---|---|---|
| VPC | `vpc-0767ac83c72b3cf40` | `10.0.0.0/16` |
| Public Subnet A | `subnet-092734d1357224a25` | `10.0.1.0/24`, `ap-northeast-2a` |
| Public Subnet C | `subnet-02fd34391da42563b` | `10.0.2.0/24`, `ap-northeast-2c` |
| Private Subnet A | `subnet-000d98c349b771ee1` | `10.0.11.0/24`, `ap-northeast-2a` |
| Private Subnet C | `subnet-04cc7bdb725c4f5a6` | `10.0.12.0/24`, `ap-northeast-2c` |

### 라우팅

| Route Table | 연결 | 라우팅 |
|---|---|---|
| `rtb-09c3c941b458da9fb` | public subnet A/C | `10.0.0.0/16` local, `0.0.0.0/0` → `igw-0c71eb6adda55dbaf` |
| `rtb-02a4df14844468ea8` | private subnet A/C | `10.0.0.0/16` local (외부 라우팅 없음) |
| `rtb-062f6a4eb965b312e` | main | `10.0.0.0/16` local |

- Internet Gateway: `igw-0c71eb6adda55dbaf`
- NAT Gateway: **없음** (private subnet은 아웃바운드 인터넷 경로 없음, 로컬 통신만)

### Security Group

| SG | ID | 인바운드 규칙 |
|---|---|---|
| `boaz-alb-sg` | `sg-0b98cad292282ebe5` | TCP 80 ← CloudFront prefix list `pl-22a6434b` |
| `prod-cf-to-ec2-sg` | `sg-0f687731f48f23809` | TCP 8080 ← CloudFront prefix list `pl-22a6434b` |
| `prod-alb-to-ec2-sg` | `sg-0a1b971b7c6ecca6b` | TCP 8080 ← `boaz-alb-sg`(sg-0b98cad292282ebe5) |
| `prod-ec2-to-rds-sg` | `sg-0b85c4efb533a1fe4` | (인바운드 없음, RDS 접근 source로 사용) |
| `prod-rds-sg` | `sg-031dfbcef8f27664b` | TCP 3306 ← `prod-ec2-to-rds-sg` |
| `prod-ssh-sg` | `sg-05b499bad8d9637d1` | TCP 22 ← `[개인 IP 삭제]/32`, `[개인 IP 삭제]/32` |

- SSH는 특정 IP 2개로만 제한됨 (0.0.0.0/0 전체 개방 아님).
- 평시에 ALB는 없지만 `boaz-alb-sg`, `prod-alb-to-ec2-sg`는 시즌 재사용을 위해 상시 유지된다.

---

## 4. 컴퓨팅 (EC2)

| 항목 | EC2-A | EC2-B |
|---|---|---|
| Name | `boaz-api-prod-A` | `boaz-api-prod-B` |
| Instance ID | `i-08bb34407c19504cf` | `i-05405847d3897364a` |
| 상태 | running (상시) | stopped (시즌에만 기동) |
| Type | `t3.small` | `t3.small` |
| AZ / Subnet | `2a` / `subnet-092734d1357224a25` | `2c` / `subnet-02fd34391da42563b` |
| Instance Profile | `role-prod-ec2` | `role-prod-ec2` |

- 두 인스턴스 모두 SG 4개 부착: `prod-ec2-to-rds-sg`, `prod-ssh-sg`, `prod-cf-to-ec2-sg`, `prod-alb-to-ec2-sg`
- 애플리케이션: Spring Boot, 포트 8080, systemd `boaz.service`, health `/actuator/health`

---

## 5. 로드밸런싱

| 항목 | 값 |
|---|---|
| Target Group | `boaz-api-tg` (`arn:...:targetgroup/boaz-api-tg/d42747d4f4ff49e6`) |
| 프로토콜/포트 | HTTP / 8080 |
| Health Check | `/actuator/health` |
| 등록 대상(평시) | EC2-A만 (상태 `unused` — 평시 ALB 미연결) |
| ALB | **평시 없음**. 시즌마다 `boaz-alb`로 생성/삭제 (DNS 매번 변경) |

---

## 6. 데이터베이스 (RDS)

| 항목 | 값 |
|---|---|
| 식별자 | `boaz-prod-db` |
| 엔진 | MySQL `8.4.11` |
| 인스턴스 클래스 | `db.t3.micro` |
| 스토리지 | `gp3`, 20 GB, 암호화 ON |
| Multi-AZ | false (평시 Single-AZ, 시즌 Multi-AZ) |
| 퍼블릭 접근 | 비활성 |
| 백업 보관 | 7일 |
| 포트 | 3306 |
| Subnet Group | `boaz-prod-rds-subnet-group` (private subnet A/C) |
| Parameter Group | `boaz-prod-mysql84` |
| Security Group | `prod-rds-sg` (`sg-031dfbcef8f27664b`) |

---

## 7. 스토리지 (S3)

| 버킷 | 용도 |
|---|---|
| `boaz-prod-frontend` | 운영 프론트(www) 정적 호스팅 origin |
| `boaz-dev-frontend` | dev 프론트 |
| `boaz-prod-frontend-admin` | admin 프론트 origin |
| `boaz-codedeploy-bucket` | 백엔드 CodeDeploy 배포 번들 |
| `boaz-recruitment` | 지원서 업로드 |
| `boaz-archiving` | 아카이빙 |
| `boaz-website`, `boaz-website-dev`, `boazweb`, `survey-*.bigdataboaz.com` | 기타/레거시 (용도 확인 필요) |

> 버킷별 버저닝/암호화/퍼블릭 차단/lifecycle 세부는 착수 시점에 버킷 단위로 재확인 필요 (일부 미설정으로 관측됨).

---

## 8. CDN (CloudFront)

| Distribution | Alias | Origin | 상태 |
|---|---|---|---|
| `E2SER81QYNPRO9` | `api.bigdataboaz.com` | EC2-A 퍼블릭 DNS, custom origin **port 8080** | Deployed |
| `EAK2LBIAYWPBV` | `www.bigdataboaz.com` | `boaz-prod-frontend` S3 | Deployed |
| `E2GM63NBDWPND0` | `admin.bigdataboaz.com` | `boaz-prod-frontend-admin` S3 | Deployed |

- api 배포는 **단일 custom origin** 구조 (EC2-A 직결 ↔ ALB 사이 교체).
- www/admin 배포는 S3 origin, SPA 라우팅.

---

## 9. DNS / 인증서

| 항목 | 값 |
|---|---|
| Hosted Zone | `bigdataboaz.com` (`Z06161783647LR0PZWA47`), 레코드 15개 |
| 주요 레코드 | `api` → api CloudFront, `www` → www CloudFront, `admin` → admin CloudFront |
| ACM | CloudFront viewer 인증서는 `us-east-1` 리전 (상세 미확인, 착수 시 확인) |

---

## 10. 배포 파이프라인

### Backend (EC2 + CodeDeploy)

| 항목 | 값 |
|---|---|
| CodeDeploy App | `boaz-backend` |
| Deployment Group | `codedeploy-prod` |
| 대상 태그 | `app=boaz-api` |
| 배포 설정 | `CodeDeployDefault.AllAtOnce` |
| Service Role | `role-prod-codedeploy` |
| 흐름 | GitHub Actions → S3(`boaz-codedeploy-bucket`) 번들 업로드 → CodeDeploy → EC2 systemd |

### Frontend (S3 + CloudFront)

| 항목 | 값 |
|---|---|
| 흐름 | GitHub Actions → `aws s3 sync dist/` → CloudFront invalidation |
| dev 배포 | `dev` 푸시 → dev 버킷 |
| www 배포 | `main` 푸시 → `boaz-prod-frontend` |

---

## 11. IAM / OIDC

| Role / Provider | 용도 |
|---|---|
| `role-prod-github-actions` | 백엔드 GitHub Actions OIDC (배포) |
| `role-prod-github-actions-frontend` | 프론트 GitHub Actions OIDC (배포) |
| `role-prod-codedeploy` | CodeDeploy 서비스 롤 |
| `role-prod-ec2` | EC2 instance profile (SSM/S3/CloudWatch/CodeDeploy) |
| GitHub OIDC Provider | `token.actions.githubusercontent.com` |

---

## 12. 파라미터 (SSM Parameter Store)

| 구분 | 개수 | 내용 |
|---|---|---|
| 인프라 식별자 `/boaz/infra/*` | 12개 | `EC2_B_ID`, `EC2_A_DOMAIN`, `EC2_A_PORT`, `CLOUDFRONT_DIST_ID`, `RDS_IDENTIFIER`, `S3_BUCKET`, `CODEDEPLOY_APP`, `CODEDEPLOY_GROUP`, `TARGET_GROUP_ARN`, `ALB_SG_ID`, `ALB_SUBNETS`, `ALB_PORT` |
| 앱 시크릿 (루트 경로) | 14개 | `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `S3_RECRUITMENT_BUCKET_NAME`, `S3_ARCHIVING_BUCKET_NAME`, `KAKAO_*`, `GOOGLE_*`, `NAVER_*`, `SWAGGER_*` |

> 앱 시크릿 값은 조회하지 않음. SecureString 여부는 착수 시 확인.

---

## 13. 시즌 전환 동작 (현행)

모집 시즌에 `season-up.sh` / `season-down.sh`가 AWS CLI로 절차적으로 수행하는 상태 변화.

| 대상 | 평시 | 시즌중 |
|---|---|---|
| ALB `boaz-alb` + listener(:80) | 없음 | 생성 |
| EC2-B | stopped, `app=boaz-api` 태그 없음 | running, 태그 부착 |
| Target Group 등록 | EC2-A만 | EC2-A + EC2-B |
| CloudFront api origin | EC2-A:8080 | ALB DNS:80 |
| RDS `multi_az` | false | true |

- 시즌 종료 시 CloudFront origin을 EC2-A로 복귀 → `Deployed` 확인 후 ALB 삭제 (전파 전 삭제 시 502 발생).
- 영구 유지 리소스: Target Group `boaz-api-tg`, `boaz-alb-sg`, `prod-alb-to-ec2-sg`, EC2-B(중지 상태), `/boaz/infra/*`.

---

## 14. 관측된 특이사항

- api CloudFront origin이 EC2-A **퍼블릭 DNS 문자열**에 의존. EC2-A에 EIP(`eipalloc-0d58d66169c7560bb`)가 연결되어 있어 재시작해도 DNS는 유지됨 (2026-09-23 조사 기준, `docs/inventory.md` 참조).
- RDS Multi-AZ를 시즌마다 토글하는 구조 (가용성 설정을 트래픽 이벤트에 연동).
- private subnet에 NAT 없음 → private subnet 리소스는 아웃바운드 인터넷 불가.
- GitHub OIDC trust에 동일 repo subject가 중복 기재됨 (동작 무해).

---

## 참고

- 마이그레이션 계획: [`terraform-migration-plan.md`](./terraform-migration-plan.md)
- 마이그레이션 요구사항 명세(EARS): [`../.kiro/specs/product-infra-migration/requirements.md`](../.kiro/specs/product-infra-migration/requirements.md)
- 현행 시즌 운영 스크립트/절차: `backend/infra/scripts/README.md`
