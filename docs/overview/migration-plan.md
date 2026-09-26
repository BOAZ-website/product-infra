# Terraform 이전 계획 (배경·원칙)

운영 중인 BOAZ 홈페이지(`www.bigdataboaz.com`)와 API 서버(`api.bigdataboaz.com`)의 AWS 인프라를 서비스 중단 없이 Terraform 코드로 옮기는 작업의 목표, 원칙, 시즌 전환 모델을 정리한 문서.

> 작업 순서·티켓·완료 조건은 WBS(`docs/wbs/00-wbs.md`)를 따름. 그룹별 import 방법은 `docs/guides/import-procedure.md`를 따름. 이 문서는 "왜, 어떤 원칙으로"만 다룸

---

## 1. 목표 / 비목표

### 목표

1. 운영(prod) 환경의 AWS 자원을 **다시 만들지 않고 Terraform state로 import**함. 서비스 중단 0.
2. 시즌 전환(ALB 생성·삭제, EC2-B 기동·중지, RDS Multi-AZ 전환, CloudFront origin 교체)을 코드로 제어하고 기존 셸 스크립트를 폐기함
3. 인프라 변경을 **PR → plan 리뷰 → 머지 → 승인 후 apply** 흐름으로 옮김
4. 인프라 코드를 애플리케이션 저장소와 분리해 `product-infra`에서 관리함

### 비목표

- 관리자 콘솔 신규 환경 구성. 단, **이미 있는 admin S3·CloudFront·Route53 자원의 import는 범위 안**
- 백엔드 dev 환경 신설
- 구조 변경(ECS·EKS·ASG, Blue-Green 등). 이번 작업은 현행 구조를 그대로 코드로 옮기는 데 한정
- 애플리케이션 코드, CodeDeploy 훅, Spring 설정, 기존 배포 workflow 변경. infra 저장소가 앱 workflow를 바꾸지 않음

---

## 2. 현행 구조

```text
평시(off):
  사용자 → Route53 → CloudFront(api) → EC2-A:8080 → RDS(Single-AZ)
  사용자 → Route53 → CloudFront(www/admin) → S3 정적 호스팅
  EC2-B: stopped, ALB: 없음, Target Group: EC2-A만 등록(미사용)

시즌(on):
  사용자 → Route53 → CloudFront(api) → ALB:80 → EC2-A/EC2-B:8080 → RDS(Multi-AZ)
```

- 리전 `ap-northeast-2`. CloudFront 인증서만 `us-east-1`
- backend: EC2 + CodeDeploy(systemd `boaz.service`)
- frontend·admin: S3 + CloudFront, 각 CloudFront(api 포함)에 WAF 연결
- 직접 접근 제한: ALB 보안 그룹은 TCP 80을 CloudFront 관리형 prefix list(`com.amazonaws.global.cloudfront.origin-facing`)에서만 허용. EC2 보안 그룹은 TCP 8080을 ALB 보안 그룹과 CloudFront prefix list에서만 허용. prefix list는 모든 CloudFront 배포를 포함하므로 BOAZ 배포에서 온 요청만 받도록 하는 오리진 보호는 별도 보완 항목(관리자 CloudFront 보안 설정)에서 다룸
- EC2-A에는 Elastic IP가 연결되어 있음
- 현재 IaC 없음. 시즌 전환은 `backend/infra/scripts/`의 셸·파이썬 스크립트로 수행
- 자원별 실제 식별자는 `docs/records/inventory.md`(조사 기록)에만 적음. 다른 문서에는 역할명(EC2-A, api CloudFront 등)으로 씀

---

## 3. 저장소 구조

```text
product-infra/
├── bootstrap/                state 저장용 S3 버킷. 최초 1회, prevent_destroy
├── envs/prod/                운영 환경. 그룹별 파일로 분리
│   ├── versions.tf providers.tf backend.tf variables.tf outputs.tf   (공통, 리드만 수정)
│   ├── network.tf iam.tf params.tf storage.tf compute.tf database.tf cdn.tf deploy.tf
│   └── imports/<그룹>.tf     그룹별 import 블록
├── modules/                  network compute database storage cdn deploy iam params
├── tests/                    property·통합·정적 검사
├── docs/                     문서 (docs/README.md 참조)
└── .github/workflows/        PR 검사, 승인 후 apply, drift 감지
```

- Terraform `>= 1.11.0, < 2.0.0`. S3 자체 잠금(`use_lockfile`)은 1.10에서 도입, 1.11에서 정식 기능
- AWS provider 버전 범위 고정, `.terraform.lock.hcl` 커밋
- 기본 태그: `Project=boaz`, `Environment=prod`, `ManagedBy=terraform`, `Repository=product-infra`. 모든 그룹 import가 끝나고 plan "No changes"를 확인한 뒤 태그 추가 전용 PR로 적용
- state: 전용 S3 버킷(버전 관리·암호화·퍼블릭 차단) + `use_lockfile = true`, 키 `envs/prod/terraform.tfstate`

---

## 4. 시즌 전환 모델

한 번의 apply로는 "ALB가 준비된 뒤에 origin 교체", "CloudFront 반영이 끝난 뒤에 ALB 삭제" 순서를 보장할 수 없어서 변수 2개로 나눔

| 변수 | 값 | 제어 대상 |
| --- | --- | --- |
| `season_capacity` | `off` / `on` | ALB·listener, EC2-B 기동과 기능 태그, Target Group 등록 대상, RDS Multi-AZ |
| `api_origin` | `ec2` / `alb` | api CloudFront origin (EC2-A:8080 / ALB:80) |

- `api_origin = alb`이면 `season_capacity = on`이어야 함(사전 조건으로 강제)
- 시즌 시작: EC2-B 기동(런북 단계, CLI) → **최신 번들 재배포 성공** → `season_capacity = on` apply(ALB 생성, EC2-B Target Group 등록, Multi-AZ) → Target Group 대상 정상 확인 → `api_origin = alb` apply. 현행 `season-up.sh`와 같은 순서로, 재배포가 끝나기 전에는 EC2-B를 Target Group에 등록하지 않음
- 시즌 종료: `api_origin = ec2` apply → CloudFront `Deployed` 확인 → `season_capacity = off` apply. 반영 전에 ALB를 지우면 502
- RDS Multi-AZ 전환은 수십 분 걸리므로 별도 단계로 분리
- EC2-B 켜기·끄기는 `aws_ec2_instance_state` 사용

2026년 12월 시즌은 기존 스크립트로 전환하고 그 기간 Terraform apply는 금지함. Terraform 전환은 2027년 비시즌 리허설 2회 성공 뒤부터

---

## 5. 안전 원칙

- 서비스 중단 불가. RDS·EC2·EIP·CloudFront·Route53·S3는 교체(replace) 금지 → `prevent_destroy`
- plan에 삭제·교체가 있으면 승인 없이 apply 금지
- 조사로 확정되지 않은 식별자로 import·apply 금지(추정값 금지)
- 시크릿·비밀번호는 코드·tfvars·plan·로그에 두지 않음(`ignore_changes`, `sensitive`)
- 기존 배포 workflow가 참조하는 이름·버킷·배포 ID·롤 ARN 유지(Terraform output으로 계약 검사)
- 콘솔 수동 변경 금지. 장애 대응 중 변경했다면 즉시 기록하고 3일 안에 코드 반영(시즌 동결 중이면 동결 종료 후 3일 안에)
- "state 등록만 하는 apply(import)"와 "자원을 바꾸는 apply"를 구분해 리뷰함

---

## 6. 주요 위험과 대응

| 위험 | 영향 | 대응 |
| --- | --- | --- |
| import 시 속성 불일치로 교체 plan | 운영 자원 삭제 | `prevent_destroy` 먼저 적용, 그룹 단위 import, 안전 게이트(STA-07) |
| CloudFront origin 교체 중 반영 지연 | 502·5xx | origin 복귀 → `Deployed` 확인 → ALB 삭제 순서 |
| 시즌 시작 때 EC2-B가 옛 버전 앱으로 서비스 | 버전 혼재, 스키마 불일치 | 재배포 성공 후에만 `season_capacity = on`으로 Target Group 등록 |
| RDS 비밀번호가 state에 기록 | 시크릿 유출 | `ignore_changes = [password]`, state 버킷 암호화·접근 제한 |
| import 중 스크립트로 시즌 전환 | state와 실제 불일치, 잘못된 apply | 시즌 동결 기간 apply 금지, 전환 수단 하나로 통일 |
| 콘솔 수동 변경 | 예기치 않은 apply | 일일 drift 감지 |

---

## 7. 완료 기준

1. `envs/prod`에서 `terraform plan` → "No changes. Your infrastructure matches the configuration."
2. 조사 목록의 모든 항목이 import됐거나 "관리 제외" 사유와 함께 기록됨
3. 시즌 on → 확인 → off 리허설 성공(ALB 생성·삭제, 대상 정상, origin 값, Multi-AZ, API 상태 확인 정상)
4. 리허설 중 5xx 없음
5. backend 수동 배포 성공, frontend dev·main 배포 성공
6. PR 검사·승인 후 apply 파이프라인 동작
7. 런북·import 기록·README 작성
8. 구 스크립트 4종 deprecated 표시

---

## 8. 후속 작업(범위 밖)

1. 관리자 콘솔 신규 환경 구성(개발 완료 후)
2. 백엔드 dev 환경 코드화
3. SSM 앱 시크릿 경로 이관(`/boaz/app/*`), `load-ssm-env.sh` 동시 변경 필요
4. 경보 확장(기본 경보는 OBS-01에서 이번 범위에 포함)
