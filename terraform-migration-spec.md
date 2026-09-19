# BOAZ 인프라 Terraform 마이그레이션 — 요구사항 명세 (Kiro 전달용)

- 문서 버전: v1.0 (2026-09-19)
- 대상: Kiro spec 세션 입력 (`requirements.md` 기준 포맷, EARS 표기)
- 작성 근거: `BOAZ-website/backend`, `BOAZ-website/frontend` 저장소의 워크플로·배포 스크립트·인프라 스크립트 실사

---

## 1. 배경

BOAZ 공식 홈페이지(`www.bigdataboaz.com`)와 API 서버는 현재 **IaC 없이 AWS 콘솔 수작업 + bash 스크립트**로 운영된다.

- 저장소 어디에도 `.tf` 파일이 없다. 인프라 정의의 유일한 흔적은 `backend/infra/scripts/`의 bash/python 스크립트와 `register-ssm-params.sh`에 하드코딩된 리소스 식별자 12개다.
- 리소스 식별자(인스턴스 ID, TG ARN, SG ID, 서브넷 ID, CloudFront 배포 ID)가 셸 스크립트와 SSM Parameter Store에 평문으로 흩어져 있다.
- 모집 시즌(연 2회, 각 2주) 전환은 `season-up.sh` / `season-down.sh`가 AWS CLI를 절차적으로 호출해 수행한다. 실패 시 **콘솔 수동 롤백**이 유일한 복구 수단이다(스크립트 README에 롤백 절차가 명시되어 있음).
- Target Group, ALB SG, EC2-B 등 "영구 유지 리소스"는 콘솔에서 최초 1회 수동 생성하도록 문서화되어 있어, 재현·감사·drift 탐지가 불가능하다.

## 2. 목표 / 비목표

### 목표
1. 현재 **운영(prod) 환경에 살아 있는 AWS 리소스 전체를 Terraform state로 import**한다. 리소스를 재생성하지 않으며 서비스 중단이 없어야 한다.
2. 시즌 전환(ALB 생성/삭제, EC2-B 기동/중지, RDS Multi-AZ 토글, CloudFront origin 교체)을 **Terraform 변수 하나로 제어**하고 기존 bash 스크립트를 폐기한다.
3. 인프라 변경을 **PR → `terraform plan` 리뷰 → 머지 → `apply`** 흐름으로 옮긴다.
4. 인프라 코드를 **별도 저장소(`BOAZ-website/infra`)** 로 분리해 애플리케이션 배포 파이프라인과 수명주기를 떼어낸다.

### 비목표 (이번 범위 아님)
- `admin.bigdataboaz.com` 신규 환경 구성 — 관리자 콘솔 개발 완료 후 별도 마이그레이션으로 진행한다.
- 백엔드 dev 환경 신설(현재 `application-dev.yml`은 존재하나 배포 대상 인프라가 없음).
- 아키텍처 전환(ECS/EKS/ASG 도입, Blue-Green 배포 전환 등). 이번은 **현행 구조의 코드화(lift-and-codify)** 에 한정한다.
- 애플리케이션 코드, CodeDeploy 훅 스크립트, Spring 설정 변경.

---

## 3. 현행 인프라 인벤토리 (실사 결과)

> Kiro는 이 표를 import 대상 후보 목록의 출발점으로 사용한다. `미확인` 항목은 §8의 사전 조사 태스크에서 AWS CLI로 수집한다.

**공통**: AWS 계정 `156312218841`, 리전 `ap-northeast-2`, 로컬 AWS 프로파일 `tf`

| 구분 | 리소스 | 식별자 / 값 | 출처 |
|---|---|---|---|
| 컴퓨팅 | EC2-A (상시 가동) | `ec2-[서버 공인 IP 삭제].ap-northeast-2.compute.amazonaws.com`, 포트 8080, 인스턴스 ID 미확인 | `register-ssm-params.sh` |
| 컴퓨팅 | EC2-B (평시 stopped) | `i-05405847d3897364a` | `register-ssm-params.sh` |
| 네트워크 | ALB | `boaz-alb` (시즌마다 생성/삭제, DNS 매번 변경) | `season-up.sh` |
| 네트워크 | Target Group | `arn:aws:elasticloadbalancing:ap-northeast-2:156312218841:targetgroup/boaz-api-tg/d42747d4f4ff49e6` (포트 8080, HC `/actuator/health`) | `register-ssm-params.sh`, README |
| 네트워크 | ALB Security Group | `sg-0b98cad292282ebe5` (inbound: CloudFront prefix list only) | `register-ssm-params.sh` |
| 네트워크 | EC2 Security Group | ALB SG → 8080 인바운드 룰 보유, SG ID 미확인 | README |
| 네트워크 | 서브넷 | `subnet-02fd34391da42563b`, `subnet-092734d1357224a25` | `register-ssm-params.sh` |
| 네트워크 | VPC | 미확인 | — |
| DB | RDS MySQL | `boaz-prod-db`, MySQL 8.4 계열, 평시 Single-AZ / 시즌 Multi-AZ, 인스턴스 클래스·스토리지·파라미터그룹·서브넷그룹 미확인 | `season-*.sh`, `docker-compose.yaml` |
| CDN | CloudFront (api) | `E2SER81QYNPRO9`, **단일 origin** (EC2-A 직결 8080 ↔ ALB 80 사이 교체) | `cf_set_origin.py` |
| CDN | CloudFront (www) | 배포 ID 미확인 — GitHub Secret `CF_DIST_ID_WWW` | `deploy-www.yml` |
| CDN | CloudFront (dev) | 배포 ID 미확인 — GitHub Secret `CF_DIST_ID_DEV` | `deploy-dev.yml` |
| 스토리지 | 배포 번들 버킷 | `boaz-codedeploy-bucket` | `cd.yml` |
| 스토리지 | 프론트 www 버킷 | 미확인 — Secret `S3_BUCKET_WWW` | `deploy-www.yml` |
| 스토리지 | 프론트 dev 버킷 | 미확인 — Secret `S3_BUCKET_DEV` | `deploy-dev.yml` |
| 스토리지 | 지원서 업로드 버킷 | 미확인 — SSM `S3_RECRUITMENT_BUCKET_NAME` | `application-prod.yml` |
| 스토리지 | 아카이빙 버킷 | 미확인 — SSM `S3_ARCHIVING_BUCKET_NAME` | `application-prod.yml` |
| 배포 | CodeDeploy | 애플리케이션 `boaz-backend`, 배포그룹 `codedeploy-prod`, 대상 태그 `app=boaz-api` | `cd.yml`, `season-*.sh` |
| IAM | GitHub OIDC 롤 | `arn:aws:iam::156312218841:role/role-prod-github-actions` (backend), 프론트는 Secret `AWS_ROLE_ARN` | `cd.yml`, `deploy-*.yml` |
| IAM | EC2 인스턴스 프로파일 | 미확인 (SSM `GetParameter` + S3 read 권한 필요) | `load-ssm-env.sh` |
| IAM | CodeDeploy 서비스 롤 | 미확인 | — |
| DNS | Route53 | `bigdataboaz.com` — `www`, `dev`, `api`, (예정) `admin`. 호스팅 영역 ID 미확인 | `application-prod.yml` |
| 인증서 | ACM | CloudFront용(us-east-1) / ALB용 존재 여부 미확인 | — |
| 파라미터 | SSM `/boaz/infra/*` | 인프라 식별자 12개 (EC2_B_ID, EC2_A_DOMAIN, EC2_A_PORT, CLOUDFRONT_DIST_ID, RDS_IDENTIFIER, S3_BUCKET, CODEDEPLOY_APP, CODEDEPLOY_GROUP, TARGET_GROUP_ARN, ALB_SG_ID, ALB_SUBNETS, ALB_PORT) | `register-ssm-params.sh` |
| 파라미터 | SSM 앱 시크릿 | 루트 경로 14개 (`DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `S3_*_BUCKET_NAME`, `KAKAO_*`, `GOOGLE_*`, `NAVER_*`, `SWAGGER_*`). SecureString 여부 미확인 | `scripts/load-ssm-env.sh` |

### 현행 트래픽 경로

```
평시:   사용자 → Route53 → CloudFront(E2SER81QYNPRO9) → EC2-A:8080 → RDS(Single-AZ)
시즌중: 사용자 → Route53 → CloudFront(E2SER81QYNPRO9) → ALB:80 → EC2-A:8080 / EC2-B:8080 → RDS(Multi-AZ)
프론트: 사용자 → Route53 → CloudFront(www/dev) → S3 정적 호스팅
```

---

## 4. 요구사항

> 표기: EARS(Easy Approach to Requirements Syntax). `WHEN/IF <조건> THEN 시스템은 <동작>해야 한다`.

### R1. 인프라 저장소 및 디렉터리 구조

**사용자 스토리**: 운영자로서, 인프라 정의를 애플리케이션 코드와 분리된 한 곳에서 관리하고 싶다. 인프라 변경과 앱 배포의 수명주기가 다르기 때문이다.

**수용 기준**
1. 시스템은 인프라 코드를 신규 저장소 `BOAZ-website/infra`에 두어야 한다.
2. 시스템은 재사용 가능한 단위를 `modules/`(network, compute, database, storage, cdn, deploy, iam, params)로, 환경별 진입점을 `envs/prod/`로 분리해야 한다.
3. 시스템은 현재 운영 환경만 `envs/prod`로 정의하되, `envs/<env>` 추가만으로 환경을 늘릴 수 있는 구조여야 한다.
4. WHEN 개발자가 모듈을 수정하면 THEN 해당 모듈은 하드코딩된 계정 ID·리전·리소스 ID 없이 변수로만 동작해야 한다.
5. 시스템은 Terraform ≥ 1.9, AWS Provider ≥ 5.x 로 버전을 고정(`required_version`, `required_providers`)해야 한다.
6. 시스템은 `.terraform.lock.hcl`을 저장소에 커밋해야 한다.

### R2. 상태(state) 관리

**사용자 스토리**: 운영자로서, 여러 사람이 동시에 apply해도 상태가 깨지지 않기를 바란다.

**수용 기준**
1. 시스템은 Terraform state를 S3 백엔드에 저장해야 한다(버킷은 전용 신규 버킷, 버저닝·SSE·퍼블릭 액세스 차단 활성화).
2. 시스템은 S3 네이티브 락(`use_lockfile = true`)을 사용해야 한다. IF 조직 표준이 DynamoDB 락을 요구한다 THEN 락 테이블 방식을 대안으로 제시해야 한다.
3. 시스템은 state 버킷과 락 리소스를 **부트스트랩 구성(`bootstrap/`)으로 분리**하고, 해당 리소스에 `prevent_destroy`를 적용해야 한다.
4. 시스템은 환경별로 state 키를 분리해야 한다(예: `prod/terraform.tfstate`).
5. 시스템은 state 파일에 평문 시크릿이 들어가지 않도록 §R9의 파라미터 정책을 따라야 한다.

### R3. 기존 운영 리소스 무중단 import

**사용자 스토리**: 운영자로서, 이미 서비스 중인 리소스를 코드화하되 단 한 번의 다운타임도 발생시키고 싶지 않다.

**수용 기준**
1. 시스템은 모든 기존 리소스를 **`import` 블록(Terraform 1.5+ 선언적 import)** 으로 취득해야 하며, 리소스를 삭제 후 재생성해서는 안 된다.
2. WHEN import를 수행하면 THEN 동일 커밋에서 `terraform plan`이 **"No changes"** 를 출력해야 한다. 이것이 각 리소스의 import 완료 판정 기준이다.
3. IF plan에 `destroy` 또는 `replace`가 하나라도 포함된다 THEN apply를 금지하고 해당 리소스 정의를 실제 상태에 맞춰 수정해야 한다.
4. 시스템은 import를 리소스 그룹 단위로 나눠 단계적으로 수행해야 한다. 권장 순서: ① 네트워크(VPC/서브넷/SG) → ② IAM/SSM → ③ 스토리지(S3) → ④ 컴퓨팅(EC2) → ⑤ DB(RDS) → ⑥ 로드밸런싱(TG) → ⑦ CDN/DNS(CloudFront, Route53, ACM) → ⑧ 배포(CodeDeploy).
5. 시스템은 각 단계마다 import 대상 목록·`plan` 결과·잔여 diff를 문서로 남겨야 한다.
6. 시스템은 Terraform이 관리하지 않기로 한 리소스(예: 기본 VPC 부속 리소스, 콘솔 자동 생성 서비스 링크드 롤)를 `데이터 소스` 또는 `관리 제외 목록`으로 명시 구분해야 한다.
7. 시스템은 운영 중단을 유발할 수 있는 리소스(RDS, EC2, CloudFront, Route53 레코드)에 `lifecycle { prevent_destroy = true }`를 적용해야 한다.

### R4. 네트워크

**수용 기준**
1. 시스템은 기존 VPC·서브넷(`subnet-02fd34391da42563b`, `subnet-092734d1357224a25`)·라우팅 테이블·인터넷 게이트웨이를 import하여 코드로 표현해야 한다.
2. 시스템은 ALB SG(`sg-0b98cad292282ebe5`)의 인바운드를 **CloudFront 관리형 prefix list(`com.amazonaws.global.cloudfront.origin-facing`)** 로만 허용하는 현행 규칙을 유지해야 한다.
3. 시스템은 EC2 SG에 "ALB SG → TCP 8080" 인바운드 룰을 코드로 정의해야 한다.
4. 시스템은 보안 그룹 규칙을 `aws_vpc_security_group_ingress_rule` / `_egress_rule` 개별 리소스로 정의해야 한다(인라인 `ingress` 블록 금지 — drift 추적 불가).
5. IF 현재 SG에 0.0.0.0/0 SSH 등 과도한 개방 규칙이 존재한다 THEN 코드화 시 이를 보고하고 축소안을 제시해야 한다(임의 변경은 금지, 별도 승인 후 반영).

### R5. 컴퓨팅 (EC2)

**수용 기준**
1. 시스템은 EC2-A와 EC2-B(`i-05405847d3897364a`)를 각각 import해야 한다.
2. 시스템은 EC2 인스턴스에 AMI·user_data 변경으로 인한 **재생성이 발생하지 않도록** `lifecycle { ignore_changes = [ami, user_data, tags["aws:..."]] }` 등 필요한 예외를 명시해야 한다.
3. 시스템은 CodeDeploy 대상 태그 `app=boaz-api`의 부착/해제가 시즌 상태에 따라 달라짐을 R10에 따라 처리해야 한다.
4. 시스템은 EC2 인스턴스 프로파일과 그 IAM 정책(SSM `GetParameter`/`GetParameters` with decryption, 배포 번들 S3 read, CodeDeploy 에이전트 권한)을 코드로 정의해야 한다.
5. 시스템은 EC2-A의 퍼블릭 DNS가 재시작 시 변경되는 위험을 제거하기 위해 **Elastic IP 도입을 권고안으로 제시**해야 한다(현재 CloudFront origin이 퍼블릭 DNS 문자열에 의존). 실제 적용 여부는 승인 후 결정한다.

### R6. 데이터베이스 (RDS)

**수용 기준**
1. 시스템은 `boaz-prod-db`와 그 서브넷 그룹·파라미터 그룹·보안 그룹을 import해야 한다.
2. 시스템은 `multi_az` 속성을 시즌 변수(R10)에 연동해야 한다.
3. 시스템은 마스터 비밀번호를 Terraform 코드·변수 파일·state에 평문으로 두어서는 안 된다. `ignore_changes = [password]` 또는 관리형 시크릿 방식을 사용해야 한다.
4. 시스템은 `deletion_protection = true`, `skip_final_snapshot = false`를 강제해야 한다.
5. WHEN `multi_az` 변경이 plan에 포함되면 THEN 해당 변경이 in-place 수정(재생성 아님)임을 plan 출력으로 확인해야 한다.

### R7. 스토리지 (S3) 및 CDN/DNS

**수용 기준**
1. 시스템은 다음 버킷을 import해야 한다: 배포 번들(`boaz-codedeploy-bucket`), 프론트 www, 프론트 dev, 지원서 업로드, 아카이빙.
2. 시스템은 각 버킷의 버저닝·암호화·퍼블릭 액세스 차단·라이프사이클·버킷 정책을 **별도 리소스**(`aws_s3_bucket_versioning` 등)로 정의해야 한다.
3. 시스템은 배포 번들 버킷에 오래된 번들을 정리하는 라이프사이클 규칙을 제안해야 한다(현재 `deploy-bundle-<sha>.zip`이 무기한 누적됨).
4. 시스템은 CloudFront 배포 3종(api / www / dev)과 Route53 레코드, ACM 인증서를 import해야 한다.
5. 시스템은 api 배포의 origin이 현재 **커스텀 origin 1개**라는 전제(`cf_set_origin.py`가 origin 개수 1을 강제)를 유지하고, origin domain/port를 시즌 변수로 전환해야 한다.
6. 시스템은 프론트 배포의 SPA 라우팅(403/404 → `/index.html`) 및 캐시 정책이 현행과 동일하게 유지되도록 코드화해야 한다.

### R8. 배포 파이프라인 리소스

**수용 기준**
1. 시스템은 CodeDeploy 애플리케이션 `boaz-backend`, 배포 그룹 `codedeploy-prod`(대상 태그 `app=boaz-api`, 배포 설정 `AllAtOnce`)를 import해야 한다.
2. 시스템은 GitHub Actions OIDC 공급자와 롤 `role-prod-github-actions`, 프론트 배포용 롤을 import하고 정책을 코드로 표현해야 한다.
3. 시스템은 기존 CI/CD 워크플로(`backend/.github/workflows/cd.yml`, `frontend/.github/workflows/deploy-*.yml`)가 **수정 없이 계속 동작**하도록 리소스 이름·ARN을 보존해야 한다.
4. 시스템은 Terraform output으로 각 워크플로가 참조하는 값(버킷명, CloudFront 배포 ID, 롤 ARN, CodeDeploy 앱/그룹명)을 노출해야 한다.

### R9. 파라미터 및 시크릿 관리

**사용자 스토리**: 운영자로서, 시크릿이 Terraform state나 Git에 남지 않기를 바란다.

**수용 기준**
1. 시스템은 SSM 파라미터를 두 부류로 구분해야 한다.
   - **인프라 식별자**(`/boaz/infra/*` 12개): Terraform이 값까지 관리한다. 값은 다른 리소스의 attribute를 참조해 생성한다(하드코딩 금지).
   - **앱 시크릿**(`DB_*`, `JWT_SECRET`, OAuth 클라이언트, `SWAGGER_*` 등 14개): Terraform은 **파라미터의 존재·타입·KMS 키만** 관리하고 값은 `ignore_changes = [value]`로 제외한다.
2. 시스템은 앱 시크릿 파라미터 타입을 `SecureString`으로 통일하는 것을 권고안으로 제시해야 한다.
3. WHEN 마이그레이션이 완료되면 THEN `/boaz/infra/*` 값은 Terraform이 관리하는 리소스 attribute에서 파생되어야 하며, `register-ssm-params.sh`는 폐기되어야 한다.
4. 시스템은 앱 시크릿 파라미터 이름이 루트 경로(`DB_URL` 등)에 평평하게 놓여 있는 현행을 `/boaz/app/*` 네임스페이스로 이관하는 안을 **후속 과제로만 기록**해야 한다(이번 범위에서는 이름을 바꾸지 않는다 — `load-ssm-env.sh`와 동시 변경이 필요하므로).

### R10. 시즌 전환의 변수화 (핵심 요구사항)

**사용자 스토리**: 운영자로서, 모집 시즌 시작·종료를 변수 하나 바꾸고 apply하는 것으로 끝내고 싶다. bash 스크립트가 중간에 실패하면 콘솔에서 수동 복구해야 하기 때문이다.

**수용 기준**
1. 시스템은 단일 변수 `season_mode`(예: `"off" | "on"`, 또는 `bool season_active`)로 다음을 일괄 제어해야 한다.

   | 대상 | `off` (평시) | `on` (시즌 중) |
   |---|---|---|
   | ALB `boaz-alb` + listener(:80) | 미생성 | 생성 |
   | EC2-B | stopped, 태그 `app=boaz-api` 없음 | running, 태그 부착 |
   | Target Group 등록 | EC2-A만 | EC2-A + EC2-B |
   | CloudFront api origin | EC2-A 도메인:8080 | ALB DNS:80 |
   | RDS `multi_az` | false | true |

2. 시스템은 `count`/`for_each`와 조건식으로 위 전환을 표현해야 하며, 전환을 위해 별도 스크립트 실행을 요구해서는 안 된다.
3. 시스템은 EC2 인스턴스 상태(running/stopped)를 Terraform으로 제어할 수 없는 경우(`aws_instance`는 상태 관리 미지원) 대안을 설계에 명시해야 한다. 후보: (a) `aws_ec2_instance_state` 리소스 사용, (b) EC2-B를 min=0/1 ASG로 전환. 두 안의 트레이드오프를 비교해 제시해야 한다.
4. WHEN `season_mode = "on"`으로 apply하면 THEN ALB 생성 → TG 헬시 → CloudFront origin 교체 순서가 **의존성 그래프로 보장**되어야 한다(헬시 이전에 origin이 교체되면 안 됨).
5. WHEN `season_mode = "off"`로 apply하면 THEN CloudFront origin 복귀가 **ALB 삭제보다 먼저 완료**되어야 한다(전파 전 ALB 삭제 시 502 발생 — 현행 `season-down.sh`가 `Deployed` 상태를 폴링하는 이유).
6. IF Terraform 의존성만으로 5번의 전파 대기를 보장할 수 없다 THEN 2단계 apply(origin 복귀 apply → 전파 확인 → ALB 제거 apply)로 분리하고 런북에 절차를 명시해야 한다.
7. 시스템은 ALB DNS 이름이 매 시즌 달라지는 현행을 유지하되, CloudFront origin이 Terraform의 ALB attribute를 참조하도록 해 수동 반영을 제거해야 한다.
8. WHEN 마이그레이션이 완료되면 THEN `season-up.sh`, `season-down.sh`, `cf_set_origin.py`, `register-ssm-params.sh`는 저장소에서 제거되거나 폐기 표시(deprecated)되어야 한다.
9. 시스템은 시즌 전환 apply를 운영 적용 전에 **리허설**해야 한다(§6 참조).

### R11. 태깅 및 네이밍

**수용 기준**
1. 시스템은 provider `default_tags`로 공통 태그를 전 리소스에 부여해야 한다: `Project=boaz`, `Environment=prod`, `ManagedBy=terraform`, `Repository=BOAZ-website/infra`.
2. 시스템은 CodeDeploy 대상 태그 `app=boaz-api` 등 **기능적 태그**를 공통 태그와 구분해 관리해야 한다.
3. 시스템은 기존 리소스 이름(`boaz-alb`, `boaz-api-tg`, `boaz-prod-db`, `boaz-codedeploy-bucket` 등)을 변경해서는 안 된다.

### R12. 인프라 CI/CD

**수용 기준**
1. WHEN infra 저장소에 PR이 열리면 THEN `terraform fmt -check`, `validate`, `plan`이 실행되고 plan 결과가 PR 코멘트로 게시되어야 한다.
2. WHEN PR이 `main`에 머지되면 THEN `terraform apply`가 실행되어야 하며, **수동 승인 게이트(GitHub Environment protection)** 를 거쳐야 한다.
3. 시스템은 CI가 AWS OIDC 롤을 사용해야 하며 장기 액세스 키를 저장해서는 안 된다.
4. 시스템은 plan 전용 롤(읽기)과 apply 롤(쓰기)을 분리해야 한다.
5. 시스템은 주기적(예: 매일) drift 감지 `plan`을 실행하고 변경 감지 시 알림을 남겨야 한다.
6. 시스템은 plan 출력에 시크릿이 노출되지 않도록 민감 변수에 `sensitive = true`를 지정해야 한다.

### R13. 문서 및 런북

**수용 기준**
1. 시스템은 `README.md`에 저장소 구조, 사전 준비(AWS 프로파일 `tf`, Terraform 버전), 일상 작업 절차를 기술해야 한다.
2. 시스템은 `docs/runbook-season.md`에 시즌 전환 절차(사전 점검 → apply → 검증 커맨드 → 실패 시 롤백)를 기술해야 한다. 기존 `backend/infra/scripts/README.md`의 검증 커맨드 5종을 계승한다.
3. 시스템은 `docs/import-log.md`에 import한 리소스와 그 결과를 기록해야 한다.
4. 시스템은 기존 `backend/infra/scripts/README.md`에 신규 저장소로의 이관 안내와 폐기 표시를 남겨야 한다.
5. 문서는 한국어로 작성한다(저장소 관례).

---

## 5. 제약 조건

1. **운영 서비스 중단 불가.** `www.bigdataboaz.com`, `api.bigdataboaz.com`은 상시 운영 중이다.
2. **리소스 재생성 금지.** RDS, EC2, CloudFront, Route53, S3는 어떤 경우에도 replace를 허용하지 않는다.
3. **기존 배포 파이프라인 무변경.** 세 애플리케이션 저장소의 워크플로 파일은 이번 작업에서 수정하지 않는다(값이 달라지면 마이그레이션 실패로 간주).
4. **리전**: `ap-northeast-2`. 단 CloudFront용 ACM은 `us-east-1`(별도 provider alias 필요).
5. **운영자 실행 환경**: Windows Git Bash 사용 이력이 있다(기존 스크립트가 `MSYS_NO_PATHCONV` 처리). Terraform 커맨드는 OS 의존성이 없어야 한다.
6. **비용**: 평시 단일 인스턴스 구성은 비용 최적화 결과다. 코드화 과정에서 상시 가동 리소스를 늘려서는 안 된다.

## 6. 인수 조건 (Definition of Done)

1. `envs/prod`에서 `terraform plan` 실행 시 **"No changes. Your infrastructure matches the configuration."** 가 출력된다.
2. §3 인벤토리의 모든 `미확인` 항목이 확정되고, 각 리소스가 import되었거나 "관리 제외" 사유와 함께 문서화되었다.
3. `season_mode = "on"` → 검증 → `season_mode = "off"` 리허설이 성공한다. 검증 항목:
   - ALB 생성/삭제 확인
   - Target Group에 EC2-A/B 모두 `healthy`
   - CloudFront origin domain/port가 의도한 값
   - RDS `MultiAZ` 상태 전환
   - `curl https://api.bigdataboaz.com/actuator/health` 정상 응답 (전환 전/중/후 모두)
4. 리허설 중 5xx 응답이 관측되지 않는다.
5. 백엔드 CD 워크플로를 수동 트리거(`workflow_dispatch`)해 배포가 성공한다.
6. 프론트엔드 `dev`/`main` 배포가 성공한다.
7. 인프라 저장소 CI에서 plan/apply 파이프라인이 동작한다.
8. 런북·import 로그·README가 작성되었다.
9. 구 스크립트 4종이 폐기 표시되었다.

## 7. 리스크

| 리스크 | 영향 | 완화 |
|---|---|---|
| import 시 속성 불일치로 replace plan 발생 | 운영 리소스 삭제 | `prevent_destroy` 선적용, plan 리뷰 필수, 단계적 import |
| CloudFront origin 교체 중 전파 지연 | 502/5xx | origin 복귀 → `Deployed` 확인 → ALB 삭제 순서 강제(R10-5, R10-6) |
| EC2-A 퍼블릭 DNS 변경 | CloudFront origin 깨짐 | EIP 도입 권고(R5-5) |
| RDS 마스터 비밀번호가 state에 기록 | 시크릿 유출 | `ignore_changes = [password]`, state 버킷 암호화·접근 제한 |
| SSM 앱 시크릿 값이 plan 출력에 노출 | 시크릿 유출 | 값 미관리(R9-1), `sensitive = true` |
| `aws_instance`로 EC2 start/stop 제어 불가 | 시즌 전환 자동화 미완성 | R10-3의 대안 설계 필요 |
| 시즌 중 수동 콘솔 변경으로 drift | apply 시 예기치 않은 변경 | 일일 drift 감지(R12-5), 콘솔 변경 금지 정책 |
| state 버킷 자체가 Terraform 관리 대상이 되는 순환 | 부트스트랩 잠김 | `bootstrap/` 분리(R2-3) |

## 8. Kiro가 먼저 수행할 사전 조사 태스크

설계(design) 단계 진입 전에 다음을 AWS CLI(`--profile tf --region ap-northeast-2`)로 수집해 §3 인벤토리의 `미확인`을 채운다.

1. VPC/서브넷/라우팅/IGW: `aws ec2 describe-vpcs`, `describe-subnets --subnet-ids subnet-02fd34391da42563b subnet-092734d1357224a25`
2. EC2-A 인스턴스 ID·SG·인스턴스 프로파일: `aws ec2 describe-instances --filters "Name=dns-name,Values=ec2-[서버 공인 IP 삭제]..."`
3. 보안 그룹 전체 규칙: `aws ec2 describe-security-groups`
4. RDS 상세: `aws rds describe-db-instances --db-instance-identifier boaz-prod-db`
5. CloudFront 배포 목록(3종 ID·origin·캐시 정책·대체 도메인): `aws cloudfront list-distributions`
6. S3 버킷 목록 및 정책·버저닝·라이프사이클: `aws s3api list-buckets` 외
7. Route53 호스팅 영역·레코드: `aws route53 list-hosted-zones`, `list-resource-record-sets`
8. ACM 인증서(ap-northeast-2 및 us-east-1): `aws acm list-certificates`
9. CodeDeploy 앱·배포그룹 설정: `aws deploy get-deployment-group --application-name boaz-backend --deployment-group-name codedeploy-prod`
10. IAM 롤·정책·OIDC 공급자: `aws iam list-roles`, `get-role`, `list-open-id-connect-providers`
11. SSM 파라미터 목록 및 타입(값 조회 금지): `aws ssm describe-parameters`
12. Target Group·ALB 현재 상태: `aws elbv2 describe-target-groups`, `describe-load-balancers`
13. 프론트 GitHub Secrets에 들어 있는 값(`S3_BUCKET_WWW`, `S3_BUCKET_DEV`, `CF_DIST_ID_WWW`, `CF_DIST_ID_DEV`, `AWS_ROLE_ARN`)은 CLI 조회 결과와 대조해 확정한다.

## 9. 미결 사항 (담당자 확인 필요)

1. state 락 방식: S3 네이티브 락 vs DynamoDB 테이블 — 조직 표준 유무.
2. EC2-A에 Elastic IP를 도입할 것인가(R5-5).
3. EC2-B 시즌 기동을 `aws_ec2_instance_state`로 갈 것인가, ASG로 갈 것인가(R10-3).
4. 앱 시크릿 SSM 파라미터를 `SecureString`으로 전환할 것인가, 전환 시점은 언제인가(R9-2).
5. 인프라 저장소의 브랜치 전략 — 애플리케이션 저장소와 동일한 `dev → main`을 쓸 것인가, `main` 단일로 갈 것인가.
6. apply 승인자 지정(GitHub Environment reviewers).

## 10. 후속 마이그레이션 (이번 범위 밖, 순서 기록)

1. **`admin.bigdataboaz.com` 환경 구성** — 관리자 콘솔(`frontend_admin`) 개발 완료 후. S3 + CloudFront + Route53 + ACM + 배포 워크플로 신규 생성. 본 마이그레이션의 프론트 모듈을 재사용한다.
2. 백엔드 dev 환경 코드화(`application-dev.yml`에 대응하는 인프라 신설 시).
3. SSM 앱 시크릿 네임스페이스 이관(`/boaz/app/*`) — `load-ssm-env.sh`와 동시 변경 필요.
4. 모니터링/알람(CloudWatch 알람, 로그 그룹) 코드화.

---

## 부록 A. 참고 파일

| 파일 | 담고 있는 정보 |
|---|---|
| `backend/infra/scripts/README.md` | 현행 아키텍처 다이어그램, 시즌 전환 절차, 영구/임시 리소스 구분, 검증 커맨드, 값 관리 정책 |
| `backend/infra/scripts/season-up.sh` | 시즌 시작 7단계 절차와 AWS API 호출 순서 |
| `backend/infra/scripts/season-down.sh` | 시즌 종료 5단계 절차, CloudFront 전파 폴링 로직 |
| `backend/infra/scripts/register-ssm-params.sh` | `/boaz/infra/*` 12개 파라미터의 실제 값 |
| `backend/infra/scripts/cf_set_origin.py` | CloudFront origin 교체 방식(단일 origin 전제) |
| `backend/.github/workflows/cd.yml` | CodeDeploy 배포 흐름, OIDC 롤 ARN, 번들 버킷 |
| `backend/appspec.yml`, `backend/scripts/*`, `backend/systemd/*` | EC2 내부 배포·기동 구조, SSM 파라미터 14종 |
| `backend/src/main/resources/application-prod.yml` | 도메인·CORS·OAuth 리다이렉트·S3 버킷 변수·로그 경로 |
| `frontend/.github/workflows/deploy-www.yml`, `deploy-dev.yml` | 프론트 S3 sync + CloudFront 무효화, Secret 이름 |
| `frontend/vercel.json` | SPA rewrite·캐시 헤더 정책(CloudFront 정책 설계 참고, 현재 미사용) |
