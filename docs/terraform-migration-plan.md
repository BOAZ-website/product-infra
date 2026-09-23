# BOAZ 인프라 Terraform 마이그레이션 플랜

운영 중인 BOAZ 홈페이지(`www.bigdataboaz.com`)와 API 서버(`api.bigdataboaz.com`)의 AWS 인프라를 **무중단으로 Terraform 코드화(lift-and-codify)** 하기 위한 종합 실행 계획이다.

- 성격: 실행 중심 종합 플랜 (요약 + 단계별 실행 + 검증)
- 상세 요구사항 명세: [`.kiro/specs/product-infra-migration/requirements.md`](../.kiro/specs/product-infra-migration/requirements.md) (EARS 표기)
- 설계/구현 태스크: [`.kiro/specs/product-infra-migration/`](../.kiro/specs/product-infra-migration/) (`design.md`, `tasks.md`)

> 이 문서는 "무엇을 어떤 순서로, 어떻게 검증하며" 진행할지를 담는다. 각 항목의 근거·수용 기준은 위 상세 문서를 참조한다.

---

## 1. 목표 / 비목표

### 목표

1. 현재 운영(prod) 환경에 살아 있는 AWS 리소스를 **재생성 없이 Terraform state로 import** 한다. 다운타임 0.
2. 시즌 전환(ALB 생성/삭제, EC2-B 기동/중지, RDS Multi-AZ 토글, CloudFront origin 교체)을 **`season_mode` 변수 하나로 제어**하고 기존 bash 스크립트를 폐기한다.
3. 인프라 변경을 **PR → `terraform plan` 리뷰 → 머지 → `apply`** 흐름으로 옮긴다.
4. 인프라 코드를 애플리케이션 저장소와 분리해 별도 저장소(`product-infra`)에서 관리한다.

### 비목표 (이번 범위 아님)

- `admin.bigdataboaz.com` 신규 환경 구성 (관리자 콘솔 개발 완료 후 별도 진행)
- 백엔드 dev 환경 신설
- 아키텍처 전환(ECS/EKS/ASG, Blue-Green 등) — 이번은 **현행 구조의 코드화**에 한정
- 애플리케이션 코드, CodeDeploy 훅, Spring 설정, 기존 배포 workflow 변경

---

## 2. 현행 아키텍처

```text
평시(season_mode=off):
  사용자 → Route53 → CloudFront(api) → EC2-A:8080 → RDS(Single-AZ)
  사용자 → Route53 → CloudFront(www/admin) → S3 정적 호스팅
  EC2-B: stopped, ALB: 없음, Target Group: EC2-A만(unused)

시즌중(season_mode=on):
  사용자 → Route53 → CloudFront(api) → ALB:80 → EC2-A/EC2-B:8080 → RDS(Multi-AZ)
```

- 계정 `156312218841`, 리전 `ap-northeast-2`
- backend: EC2 + CodeDeploy(systemd `boaz.service`)
- frontend/admin: S3 + CloudFront
- 현재 IaC 없음. 인프라의 흔적은 `backend/infra/scripts/`의 bash/python 스크립트뿐

---

## 3. 현행 인벤토리 (AWS 실측 반영)

`--profile tf --region ap-northeast-2` 기준. 아래는 read-only 실측으로 확인된 값이다. 각 리소스의 최종 import ID·현재 설정은 착수 시점에 재확인한다.

| 구분 | 리소스 | 확인된 식별자 |
|---|---|---|
| 네트워크 | VPC | `vpc-0767ac83c72b3cf40` (`10.0.0.0/16`) |
| 네트워크 | Public Subnet | `subnet-092734d1357224a25`(2a), `subnet-02fd34391da42563b`(2c) |
| 네트워크 | Private Subnet | `subnet-000d98c349b771ee1`(2a), `subnet-04cc7bdb725c4f5a6`(2c) |
| 네트워크 | SG | `boaz-alb-sg`, `prod-alb-to-ec2-sg`, `prod-cf-to-ec2-sg`, `prod-rds-sg`, `prod-ec2-to-rds-sg` |
| 네트워크 | CloudFront prefix list | `pl-22a6434b` (ALB SG inbound 80) |
| 컴퓨팅 | EC2-A (running) | `i-08bb34407c19504cf` (`t3.small`, `role-prod-ec2`) |
| 컴퓨팅 | EC2-B (stopped) | `i-05405847d3897364a` (`t3.small`, `role-prod-ec2`) |
| 로드밸런싱 | Target Group | `boaz-api-tg` (HTTP 8080, HC `/actuator/health`, EC2-A 등록/unused) |
| 로드밸런싱 | ALB | 현재 없음 (시즌에만 생성) |
| DB | RDS MySQL | `boaz-prod-db` (`db.t3.micro`, Single-AZ, 비공개, subnet group `boaz-prod-rds-subnet-group`) |
| CDN | CloudFront(api) | `E2SER81QYNPRO9` → EC2-A 직결 |
| CDN | CloudFront(www) | `EAK2LBIAYWPBV` → `boaz-prod-frontend` |
| CDN | CloudFront(admin) | `E2GM63NBDWPND0` → `boaz-prod-frontend-admin` |
| 스토리지 | S3 | `boaz-codedeploy-bucket`, `boaz-prod-frontend`, `boaz-dev-frontend`, `boaz-prod-frontend-admin`, `boaz-recruitment`, `boaz-archiving` 등 |
| DNS | Route53 | `bigdataboaz.com` (`Z06161783647LR0PZWA47`, 레코드 15) — `api/www/admin` |
| 배포 | CodeDeploy | app `boaz-backend`, group `codedeploy-prod`, 대상 태그 `app=boaz-api`, `AllAtOnce`, role `role-prod-codedeploy` |
| IAM | Role | `role-prod-github-actions`, `role-prod-github-actions-frontend`, `role-prod-codedeploy`, `role-prod-ec2` + GitHub OIDC provider |
| 파라미터 | SSM `/boaz/infra/*` | 12개 (인프라 식별자) |
| 파라미터 | SSM 앱 시크릿 | 14개 (`DB_*`, `JWT_SECRET`, OAuth, `SWAGGER_*`) — 값 미조회 |

> 실측 시 현재 상태는 정확히 `season_mode=off`(평시)와 일치했다. ALB 부재, EC2-B stopped, TG는 EC2-A만 등록(unused), CloudFront api origin은 EC2-A 직결, RDS Single-AZ.

---

## 4. 대상 저장소 구조

```text
product-infra/
├── bootstrap/                # state 저장 기반 (S3 state bucket + native lock). 최초 1회, prevent_destroy
├── envs/
│   └── prod/                 # 운영 환경 root (backend/provider/season_mode 변수)
├── modules/
│   ├── network/  compute/  database/  storage/
│   └── cdn/      deploy/   iam/       params/
├── docs/                     # 본 플랜, import-log, inventory, decisions, runbook-season
└── .github/workflows/        # fmt/validate/plan (CI), apply/drift (승인 게이트)
```

- Terraform `>= 1.9.0, < 2.0.0`, AWS provider `>= 5.0.0, < 6.0.0` 고정, `.terraform.lock.hcl` 커밋
- provider: 기본 `ap-northeast-2` + CloudFront ACM용 `aws.us_east_1` alias
- `default_tags`: `Project=boaz`, `Environment=prod`, `ManagedBy=terraform`, `Repository=product-infra`
- state: 전용 S3 버킷(버저닝/SSE/퍼블릭 차단) + S3 native lock(`use_lockfile=true`), key `envs/prod/terraform.tfstate`

---

## 5. season_mode 모델 (핵심)

단일 변수 `season_mode`(`off`/`on`)로 아래를 일괄 제어한다.

| 대상 | `off` (평시) | `on` (시즌 중) |
|---|---|---|
| ALB + listener(:80) | 없음 | 생성 |
| EC2-B | stopped, `app=boaz-api` 태그 없음 | running, 태그 부착 |
| Target Group 등록 | EC2-A만 | EC2-A + EC2-B |
| CloudFront api origin | EC2-A:8080 | ALB DNS:80 |
| RDS `multi_az` | false | true |

전환 안전 규칙:

- `on`: ALB 생성 → TG healthy → **그 다음** CloudFront origin 교체 (의존성 그래프로 순서 강제)
- `off`: CloudFront origin을 EC2-A로 복귀 → **`Deployed` 확인 후** ALB 삭제 (전파 전 ALB 삭제 시 502)
- 전파 대기를 의존성만으로 보장할 수 없으면 **2단계 apply**(origin 복귀 → 확인 → ALB 제거)로 분리하고 런북에 명시
- EC2-B start/stop은 `aws_ec2_instance_state`로 제어(대안: min=0/1 ASG — 트레이드오프는 `decisions.md`)

---

## 6. 마이그레이션 실행 단계

각 단계는 이전 단계 완료를 전제로 한다. import 판정 기준은 **동일 커밋에서 `terraform plan`이 "No changes"** 출력.

### Phase 0 — 사전 조사 / 안전 경계

- [ ] AWS CLI로 인벤토리의 모든 식별자·현재 설정 재확인 → `docs/inventory.md`
- [ ] 미결 결정(state 버킷/키, EIP 도입, EC2-B 상태 제어 방식, SecureString 전환, 승인자) → `docs/decisions.md`
- [ ] import 로그 템플릿 준비 → `docs/import-log.md`
- [ ] 시크릿 값·RDS password는 조회/기록 금지

### Phase 1 — 저장소 skeleton & bootstrap state

- [ ] `bootstrap/`, `envs/prod/`, `modules/*` skeleton 생성
- [ ] 버전/provider/alias/`default_tags`/lockfile 규칙 정의
- [ ] bootstrap으로 전용 state 버킷 생성(버저닝/SSE/퍼블릭 차단, `prevent_destroy`), native lock 권한 준비
- [ ] `envs/prod` backend를 partial config로 초기화 (bootstrap 완료 후에만)

### Phase 2 — 리소스 그룹 단위 import

권장 순서(선언적 `import` 블록 사용, replace/destroy 금지):

1. [ ] 네트워크 (VPC/Subnet/Route/IGW/SG 규칙 — 개별 `*_rule` 리소스)
2. [ ] IAM / SSM (`/boaz/infra/*` 12개는 attribute 파생, 앱 시크릿은 값 제외)
3. [ ] 스토리지 (S3 버킷 + versioning/SSE/PAB/lifecycle/policy 분리 리소스)
4. [ ] 컴퓨팅 (EC2-A/B, instance profile, `ignore_changes`로 재생성 방지)
5. [ ] DB (RDS + subnet/parameter/SG, `deletion_protection=true`, `skip_final_snapshot=false`, password 제외)
6. [ ] 로드밸런싱 (Target Group)
7. [ ] CDN/DNS (CloudFront api/www/admin, Route53, ACM은 `us-east-1`)
8. [ ] 배포 (CodeDeploy app/group, OIDC role)

각 그룹마다 import 대상·plan 결과·잔여 diff를 `docs/import-log.md`에 기록. 관리 제외 대상은 사유와 함께 명시.

### Phase 3 — season_mode 변수화

- [ ] `off`/`on` canonical 상태 모델 구현 (`count`/`for_each` + 조건)
- [ ] 전환 순서/전파 대기 안전장치 구현 및 2단계 apply 절차 문서화
- [ ] 기존 스크립트(`season-up.sh`, `season-down.sh`, `cf_set_origin.py`, `register-ssm-params.sh`) deprecated 표시

### Phase 4 — 인프라 CI/CD

- [ ] PR: `fmt -check` / `validate` / `plan` (plan 결과 PR 코멘트)
- [ ] `main` 머지: `apply` + GitHub Environment 승인 게이트
- [ ] plan 전용 role(읽기) / apply role(쓰기) 분리, OIDC only(장기 키 금지)
- [ ] 일일 drift 감지 plan, 민감 변수 `sensitive=true`

### Phase 5 — 리허설 & 전환 검증

- [ ] `season_mode=on` → 검증 → `season_mode=off` 리허설 성공
- [ ] 백엔드 CD `workflow_dispatch` 배포 성공, 프론트 dev/main 배포 성공
- [ ] 런북/import 로그/README 완비, 구 스크립트 폐기 표시

---

## 7. 안전 원칙 (불변 규칙)

- 운영 서비스 중단 불가. RDS/EC2/CloudFront/Route53/S3는 어떤 경우에도 **replace 금지** → `prevent_destroy`
- plan에 `delete`/`replace`가 있으면 승인 없이 apply 금지
- 미확정 식별자로 import/apply 금지 (추정값 사용 금지)
- 시크릿/password는 코드·tfvars·plan·로그에 두지 않음 (`ignore_changes`, `sensitive`)
- 기존 배포 workflow가 참조하는 이름·버킷·배포 ID·role ARN 보존 (Terraform output으로 계약 검사)
- 콘솔 수동 변경 금지 (drift 방지)

---

## 8. 주요 리스크와 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| import 시 속성 불일치로 replace plan | 운영 리소스 삭제 | `prevent_destroy` 선적용, 단계적 import, plan 리뷰 필수 |
| CloudFront origin 교체 중 전파 지연 | 502/5xx | origin 복귀 → `Deployed` 확인 → ALB 삭제 순서 강제 |
| EC2-A 퍼블릭 DNS 변경 | origin 깨짐 | EIP 도입 권고(승인 후) |
| RDS password가 state에 기록 | 시크릿 유출 | `ignore_changes=[password]`, state 버킷 암호화/접근 제한 |
| SSM 앱 시크릿 값 plan 노출 | 시크릿 유출 | 값 미관리, `sensitive=true` |
| `aws_instance` start/stop 미지원 | 시즌 자동화 미완성 | `aws_ec2_instance_state` 또는 ASG 대안 |
| 콘솔 수동 변경 drift | 예기치 않은 apply | 일일 drift 감지 |
| state 버킷 순환 관리 | 부트스트랩 잠김 | `bootstrap/` 분리 + `prevent_destroy` |

---

## 9. 완료 기준 (Definition of Done)

1. `envs/prod`에서 `terraform plan` → **"No changes. Your infrastructure matches the configuration."**
2. 인벤토리의 모든 항목이 import되었거나 "관리 제외" 사유와 함께 문서화됨
3. `season_mode` on → 검증 → off 리허설 성공 (ALB 생성/삭제, TG healthy, origin 값, RDS MultiAZ, `curl /actuator/health` 정상)
4. 리허설 중 5xx 미관측
5. 백엔드 CD 수동 트리거 배포 성공, 프론트 dev/main 배포 성공
6. 인프라 CI plan/apply 파이프라인 동작
7. 런북·import 로그·README 작성
8. 구 스크립트 4종 폐기 표시

---

## 10. 미결 사항 (담당자 확인 필요)

1. state 락 방식: S3 native lock vs DynamoDB (조직 표준 유무)
2. EC2-A Elastic IP 도입 여부
3. EC2-B 시즌 기동: `aws_ec2_instance_state` vs ASG
4. 앱 시크릿 SSM `SecureString` 전환 여부·시점
5. apply 승인자 지정 (GitHub Environment reviewers)

---

## 11. 후속 마이그레이션 (범위 밖, 순서 기록)

1. `admin.bigdataboaz.com` 환경 구성 (관리자 콘솔 개발 완료 후, 프론트 모듈 재사용)
2. 백엔드 dev 환경 코드화
3. SSM 앱 시크릿 네임스페이스 이관 (`/boaz/app/*`) — `load-ssm-env.sh` 동시 변경 필요
4. 모니터링/알람(CloudWatch) 코드화

---

## 참고 문서

| 문서 | 내용 |
|---|---|
| [`infra-spec.md`](./infra-spec.md) | 현행 인프라 SPEC (as-is 사실, AWS 실측 기준). 마이그레이션과 무관하게 유효한 현행 구성의 source of truth |
| [`.kiro/specs/product-infra-migration/requirements.md`](../.kiro/specs/product-infra-migration/requirements.md) | 요구사항 명세(EARS, R1~R13) — 마이그레이션 수용 기준의 source of truth |
| [`.kiro/specs/product-infra-migration/design.md`](../.kiro/specs/product-infra-migration/design.md) | 아키텍처, 저장소 구조, state/backend, 모듈 인터페이스, correctness properties |
| [`.kiro/specs/product-infra-migration/tasks.md`](../.kiro/specs/product-infra-migration/tasks.md) | 단계별 구현 태스크(선행 관계·관련 요구사항 매핑) |
| `backend/infra/scripts/README.md` | 현행 시즌 전환 절차·검증 커맨드(런북 계승 대상) |
