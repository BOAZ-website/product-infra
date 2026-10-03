# 그룹 import 공통 절차

기준일 2026-10-03

## 이 문서의 목적

- 운영 AWS 자원을 Terraform state로 가져오는(import) 그룹 작업의 공통 절차를 정함
- 대상 독자: Phase 2 그룹 담당 팀원(Terraform 처음 쓰는 팀원 포함), PR 리뷰어, apply를 실행하는 관리자
- 적용 티켓: OBS-01(신규 생성), NET-01, IAM-02, IAM-03, STO-01, CMP-01, CMP-02, RDB-01, CDN-01·CDN-02·CDN-03, DEP-01·DEP-02
- 각 명세서(`docs/wbs/2x-*.md`)에는 그 그룹에만 해당하는 항목만 있음. 이 문서의 절차는 모든 그룹이 따름
- 예외는 두 가지뿐임: obs는 기존 자원 import 없이 새로 만듦, CDN-03은 import된 자원의 설정을 바꿈(3절 완료 기준 참조)

용어

| 용어 | 뜻 |
| --- | --- |
| 그룹 | Terraform 코드 단위 9개(obs·network·iam·params·storage·compute·database·cdn·deploy). 1절 표 |
| 파트 | 팀원 배정 단위 8개(OBS·NET·IAM·STO·CMP·RDB·CDN·DEP). IAM 파트가 iam·params 두 그룹을 맡음 |
| 관리자 | AWS Admin 그룹 운영진. apply·그룹 값 갱신·잠금 강제 해제를 수행함 |
| 읽기 전용 팀원 | AWS `terraform-readonly` 그룹. 재조사·plan까지 가능함 |
| 안전 게이트 | `scripts/plan_gate.py`. plan JSON을 검사해 G1~G4 위반이면 실패함(2절) |
| 그룹 값 | 코드에 적을 수 없는 자원 ID·CIDR. SSM 파라미터 `/boaz/terraform/group-vars`에 둠(1-1절 3번) |

## 한눈에 보기

```text
착수 선언 → 재조사 → 코드 작성 → plan 맞추기 → PR·리뷰 → 머지·apply → 최종 확인 → 기록
(3절 1)     (2)       (3·4)       (5)          (6)        (7)          (8)        (9)
```

| 단계 | 누가 | 무엇을 | 결과물 |
| --- | --- | --- | --- |
| 착수 선언 | 그룹 담당 | `import-log.md` 상태 `작업 중`(작은 PR), 브랜치 생성 | import-log 행 |
| 재조사 | 그룹 담당 | 그 그룹 자원만 AWS CLI 읽기 명령으로 다시 조사 | `inventory.md` 갱신 |
| 코드 작성·plan | 그룹 담당 | 모듈·import 블록 작성, 로컬 plan에서 차이 0건 | 그룹 파일 |
| PR·리뷰 | 그룹 담당·리뷰어 | PR CI plan 코멘트 확인, 5절 체크리스트 | 승인 1건, `Apply Ready` |
| 머지·apply | 관리자 | `apply 중` 기록 → 머지 → `dev`에서 plan → 로컬 게이트 → apply | state 등록 |
| 최종 확인·기록 | 관리자·그룹 담당 | `dev`에서 plan "No changes", import-log `완료`(작은 PR) | import-log 행 |

- 착수 조건: 재조사·모듈 초안·로컬 plan은 Phase 2 1차 시작 때 8개 파트 모두 시작함(`docs/wbs/01-schedule.md`)
- 머지·apply 조건: STA-07 안전 게이트가 PR CI에서 동작해야 함. PR에 "Terraform Plan (envs/prod)" 코멘트와 게이트 결과가 붙으면 동작 중임
- 머지·apply 순서는 2절을 따름

## 처음이라면: 빠른 시작

처음 하루에 아래를 끝냄. 막히면 해당 티켓의 GitHub 이슈 코멘트로 관리자에게 질문함

- [ ] 도구 설치·버전 확인(0-3절)
- [ ] IAM 사용자 첫 로그인과 비밀번호 변경, 액세스 키로 `boaz` 프로필 등록(0-1절)
- [ ] `git clone` 후 `git config core.hooksPath .githooks` 실행(0-3절)
- [ ] `backend.hcl`·`terraform.tfvars` 준비, `init`·`plan` 성공(0-2절)
- [ ] 1-0절(파일 구조), 1-0-2절(코드 예시), 3절(작업 순서) 읽기
- [ ] 자기 그룹 명세서(`docs/wbs/2x-*.md`)와 GitHub 이슈 확인. 노션 티켓과 GitHub 이슈는 1:1이며 커밋에 쓰는 번호는 GitHub 이슈 번호임

---

## 0. 로컬 준비

그룹 작업을 시작하기 전 한 번만 함. 이 절에서 만드는 파일(`backend.hcl`, `terraform.tfvars`, `~/.aws/credentials`)은 커밋하지 않음

### 0-1. AWS 계정과 자격 증명

- 팀원은 관리자가 만든 IAM 사용자로 접근함. 콘솔 초기 비밀번호는 비공개 채널로 1회 받고 첫 로그인 때 바로 바꿈
- 권한(decisions.md "팀원 권한 범위", "apply 실행 주체")

| 구분 | 할 수 있음 | 할 수 없음 |
| --- | --- | --- |
| 관리자(Admin 그룹) | 재조사, plan, apply(한 번에 한 그룹), 그룹 값 갱신, 잠금 강제 해제, state 복구 | 없음(시크릿 조회는 규칙으로 하지 않음) |
| 읽기 전용(`terraform-readonly` 그룹) | 모든 조회, state 읽기, state 잠금 파일 쓰기, plan | 자원 생성·변경, apply, 그룹 값 갱신, 시크릿·S3 객체 내용 조회 |

- CLI 자격 증명: 각자 액세스 키를 씀(decisions.md "팀원 AWS 접근 방식")
  1. 콘솔 IAM → 본인 사용자 → 보안 자격 증명 → 액세스 키 생성
  2. `aws configure --profile boaz` 실행. 리전 `ap-northeast-2`, 출력 형식 `json` 입력
  3. `aws --profile boaz sts get-caller-identity`로 동작 확인
- 액세스 키는 `~/.aws/credentials`에 평문으로 저장됨. 커밋·공유하지 않음. 쓰지 않는 키는 비활성화함
- 프로필 이름은 모든 문서·명령에서 `boaz`로 통일함
- Terraform은 환경 변수 `AWS_PROFILE=boaz`로만 프로필을 지정함. `providers.tf`에 `profile`을 넣지 않음(공통 파일이고, PR CI의 OIDC 자격 증명과 충돌함)
- `aws login`(브라우저 로그인 임시 세션)은 관리자만 선택해 쓸 수 있음. AWS CLI 2.32 이상과 로그인 권한(`SignInLocalDevelopmentAccess`)이 필요함. 읽기 전용 그룹에는 이 권한이 없음
- 시크릿은 조회하지 않음. 읽기 전용 그룹·CI 역할은 `kms:Decrypt`, `secretsmanager:GetSecretValue`, SecureString 복호화, S3 객체 내용(state 제외)이 거부됨. 관리자 권한은 막혀 있지 않으므로 관리자도 규칙으로 조회하지 않음. import 재조사에는 `describe-*` 등 설정 조회만 필요함

### 0-2. 작업 파일 준비

| 순서 | 할 일 | 완료 확인 방법 |
| --- | --- | --- |
| 1 | `envs/prod/backend.hcl.example`을 `backend.hcl`로, `terraform.tfvars.example`을 `terraform.tfvars`로 복사. `docs/records/inventory.md`의 state 버킷 이름·계정 ID로 채움. `terraform.tfvars`에는 계정 ID(`expected_account_id`)만 들어감. 그룹 값은 넣지 않음 | 두 파일 존재, `git status`에 나타나지 않음 |
| 2 | `aws --profile boaz sts get-caller-identity`의 Account가 inventory.md 계정 ID와 같은지 확인 | Account 일치 |
| 3 | `export AWS_PROFILE=boaz` 후 `terraform -chdir=envs/prod init -input=false -lockfile=readonly -backend-config=backend.hcl` | `Successfully configured the backend "s3"!` |
| 4 | `terraform -chdir=envs/prod plan -input=false -lock-timeout=5m` | 오류 없이 plan 완료 |

- 계정 가드: provider와 backend 모두 `allowed_account_ids`가 있어 다른 계정 자격 증명이면 init·plan이 실패함
- `-lockfile=readonly`: 로컬 init이 `.terraform.lock.hcl`을 바꾸지 않게 함(CI와 같음). 잠금 파일 변경이 필요하면 STA 담당에게 요청함
- workspace는 쓰지 않음(`terraform workspace new` 금지). 쓰면 state가 `env:/` 경로로 갈라짐
- plan·apply에는 항상 `-input=false`를 붙임. 변수가 빠지면 입력을 기다리지 않고 바로 실패함
- state 잠금을 끄는 옵션(`-lock=false`)은 쓰지 않음. 대신 `-lock-timeout=5m`을 붙임(2절)

### 0-3. 도구 준비

| 도구 | 버전 | 근거 |
| --- | --- | --- |
| Terraform | `1.15.8`(최소 1.11) | `.github/workflows/ci.yml` `TF_VERSION` |
| AWS provider | 6.x | `envs/prod/versions.tf` |
| AWS CLI | v2 | `aws login`은 2.32 이상(관리자 선택) |
| tflint | `v0.64.0`(최소 0.64.0) | ci.yml, `.tflint.hcl` |
| Python | 3.12 | ci.yml Python Tests |

- 클론 후 1회: `git config core.hooksPath .githooks`
  - `pre-commit`: 민감 정보 검사(`scripts/check-sensitive.sh`)
  - `commit-msg`: 커밋 메시지 형식 `type: 설명 (#이슈번호)` 검사. 허용 type은 소문자 `feat fix docs style refactor test chore`. 끝의 `(#숫자)`가 없으면 거부됨. 예: `feat: network 모듈 VPC 추가 (#48)`
  - `--no-verify`는 쓰지 않음. 민감 정보 검사도 함께 건너뛰게 됨
- Python 테스트용 가상 환경은 저장소 밖에 만듦(`.venv/`는 `.gitignore`에 없음). 명령은 부록 A-3
- 커밋 전 로컬 검사 명령은 부록 A-3

## 1. 파일 규칙

그룹마다 자기 파일만 수정함. 다른 그룹 파일을 고쳐야 하면 그 그룹 담당에게 요청함

| 그룹 | 파트·명세서 | 모듈 폴더 | envs/prod 파일 | import 블록 파일 |
| --- | --- | --- | --- | --- |
| obs | OBS | `modules/obs/` | `envs/prod/obs.tf` | 없음(신규 생성) |
| network | NET | `modules/network/` | `envs/prod/network.tf` | `envs/prod/imports_network.tf` |
| iam | IAM | `modules/iam/` | `envs/prod/iam.tf` | `envs/prod/imports_iam.tf` |
| params | IAM | `modules/params/` | `envs/prod/params.tf` | `envs/prod/imports_params.tf` |
| storage | STO | `modules/storage/` | `envs/prod/storage.tf` | `envs/prod/imports_storage.tf` |
| compute | CMP | `modules/compute/` | `envs/prod/compute.tf` | `envs/prod/imports_compute.tf` |
| database | RDB | `modules/database/` | `envs/prod/database.tf` | `envs/prod/imports_database.tf` |
| cdn | CDN | `modules/cdn/` | `envs/prod/cdn.tf` | `envs/prod/imports_cdn.tf` |
| deploy | DEP | `modules/deploy/` | `envs/prod/deploy.tf` | `envs/prod/imports_deploy.tf` |

- 그룹 코드 PR에 함께 넣을 수 있는 문서: `docs/records/inventory.md`의 자기 그룹 부분(3절 2단계)
- `docs/records/import-log.md`는 코드 PR에 넣지 않고 작은 PR로 따로 올림(3절 1·9단계). 여러 그룹이 같은 표를 고쳐 충돌이 나기 때문임
- 공통 파일(STA 담당만 수정): `envs/prod/versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf`, `season.auto.tfvars`, `.terraform.lock.hcl`, `tests/`
- import 블록 파일은 `envs/prod/` 바로 아래 평면 파일임. Terraform은 root 디렉터리 바로 아래 `.tf`만 읽으므로 하위 폴더에 두면 무시됨
- 시즌에 따라 상태가 달라지는 자원(compute·database·cdn)은 `var.season_capacity`·`var.api_origin`을 직접 쓰지 않고 `local.season`을 모듈 입력으로 받음. 시즌 값은 `season.auto.tfvars`가 자동으로 넘김
- 그룹 사이 값 전달은 상대 그룹 모듈의 output을 참조함(예시 B). 필요한 output이 없으면 그 그룹 담당에게 추가를 요청함
- 두 그룹이 서로의 output을 참조하면 순환 참조가 됨. 한쪽은 data source로 조회함(예: storage 버킷 정책의 CloudFront 배포 ARN, `23-sto.md` STO-01-05)
- import가 끝나 state에 등록되면 import 블록을 지워도 됨. plan "No changes" 확인 뒤 별도 커밋으로 지움

### 1-0. `envs/prod/`와 `modules/`의 차이

| 구분 | `envs/prod/` (root) | `modules/<그룹>/` (모듈) |
| --- | --- | --- |
| 역할 | 운영 환경 실행 진입점. `plan`·`apply`를 여기서 실행함 | 자원 정의 묶음. 단독 실행 불가. root가 호출해야 동작함 |
| 들어가는 것 | backend·provider·계정 가드, `local.season`, `local.group_vars`, `module "<그룹>"` 호출, import 블록 | `resource`·`data` 블록, `variables.tf`, `outputs.tf`, `versions.tf` |
| state | state 하나(`envs/prod/terraform.tfstate`)에 모든 그룹 자원이 기록됨 | state 없음. 자원 주소가 `module.<그룹>.<자원>`으로 root state에 들어감 |
| 값의 출처 | 환경마다 다른 값(자원 ID, CIDR, 시즌 상태)을 정해 모듈에 넘김 | 값을 정하지 않고 입력으로 받음 |
| 수정 담당 | 공통 파일은 STA 담당, `<그룹>.tf`·`imports_<그룹>.tf`는 그룹 담당 | 그룹 담당 |

- 같은 모듈을 다른 환경에서 다른 입력으로 쓰기 위한 구조임. 일회용 dev 환경을 채택하면(decisions.md "dev 환경 신설", 대기) `envs/dev/`가 같은 모듈을 호출함
- 그룹 파일(`envs/prod/<그룹>.tf`)에는 `module "<그룹>"` 호출과 그룹 전용 variable·locals만 둠
- 모듈 입력으로 넘기는 값: 그룹 값, 시즌 값, 다른 그룹 output
- import 블록은 root에만 둘 수 있음. 모듈 안 자원은 `to = module.<그룹>.<자원>`으로 가리킴
- 각 모듈 폴더에는 뼈대 파일(`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`, 머리 주석만)이 있음. `envs/prod/<그룹>.tf`의 `module` 호출은 그룹 담당이 첫 작업 때 추가함
- us-east-1 provider: cdn·obs 모듈의 `versions.tf`에 `configuration_aliases = [aws.us_east_1]`가 선언되어 있음. 두 그룹의 `module` 호출에는 `providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`를 넘김(예시 C). 별칭 provider 자체는 `providers.tf`에 있음

팀원이 손대는 파일(network 그룹 예)

```text
product-infra/
├── modules/network/
│   ├── versions.tf, variables.tf, outputs.tf       그룹 담당 (output 이름 변경은 사용 그룹과 합의)
│   └── main.tf, vpc.tf, security_groups.tf …       그룹 담당
├── envs/prod/
│   ├── network.tf                그룹 담당 (module "network" 호출)
│   ├── imports_network.tf        그룹 담당 (import 블록)
│   ├── versions.tf, providers.tf, backend.tf, variables.tf, locals.tf,
│   │   season.auto.tfvars, .terraform.lock.hcl, tests/   STA 담당
│   ├── backend.hcl, terraform.tfvars                      커밋 금지 (gitignore)
│   └── generated.tf, plan.bin                             커밋 금지 (작업 중 임시 파일)
└── /tmp/plan.json                저장소 밖. 값이 평문이라 확인 뒤 삭제
```

### 1-0-1. 모듈 작성 규칙

- 파일 구성: `versions.tf`(provider 요구 사항. 버전 범위는 `envs/prod/versions.tf`와 같게), `variables.tf`, `outputs.tf`, 자원 파일(`main.tf` 또는 역할별 파일, 예: `vpc.tf`, `security_groups.tf`)
- 이름: 그룹에 하나뿐인 자원은 `main`, 여러 개면 역할 키(`ec2_a`, `ec2_b`, `www`, `admin` 등). 이름·`for_each` 키에 ID·IP를 쓰지 않음(자원 주소가 PR CI 코멘트에 공개됨)
- 모듈 안에 환경 이름·자원 ID·IP·계정 ID·도메인·인스턴스 타입을 고정값이나 default로 넣지 않음. 값은 root에서 넘김
- variable·output: 모두 `type`과 `description`을 적음(tflint 검사). 쓰지 않는 variable은 선언하지 않음
- 입력 이름: 시즌은 `season`(compute·database·cdn), 그룹 값은 `group_vars`(자기 그룹 부분만), 다른 그룹 값은 상대 모듈 output
- output 이름: 각 이슈 "착수 전 확인 사항"의 제안을 따름. 바꿀 때는 사용하는 그룹 담당과 합의함
- 태그: 지금은 넣지 않음. `default_tags`는 STA-09 뒤 태그 전용 PR로 적용함(decisions.md "default_tags 적용 시점")
- 보호: 명세서가 정한 보호 대상 자원에 `prevent_destroy`를 둠. `prevent_destroy`는 변수로 바꿀 수 없음. dev 환경 재사용 방식은 "dev 환경 신설" 결정 때 다시 정함
- 새 provider(예: obs의 `archive`): 실제로 쓰는 PR에서 모듈 `versions.tf`에 추가함. root 잠금 파일 갱신은 STA 담당에게 요청함

### 1-0-2. 코드 예시

network·database·cdn 그룹 기준 예시임. `example-…`, `10.0.…` 값은 형식만 맞춘 예시 값임. 실제 값은 inventory.md 기준으로 맞춤. 예시 코드는 `fmt`·`validate`·mock provider `terraform test`를 통과함

**A. envs/prod와 모듈 연결(network)**

A-1. 그룹 값 파라미터 모양. `<…>`는 실제 값 자리이며 저장소에 적지 않음

```json
{
  "network": {
    "vpc_id": "<VPC ID>",
    "private_subnet_ids": { "a": "<서브넷 ID>", "c": "<서브넷 ID>" },
    "security_group_ids": { "ssh": "<보안 그룹 ID>", "rds": "<보안 그룹 ID>" },
    "ssh_rule_ids": { "ops_1": "<규칙 ID>", "ops_2": "<규칙 ID>" },
    "ssh_allowed_cidrs": { "ops_1": "<CIDR>", "ops_2": "<CIDR>" }
  },
  "database": { "<키>": "<값>" }
}
```

- 키는 역할 키(`a`, `c`, `ssh`, `rds`, `ops_1`)로 쓰고 모듈의 `for_each` 키로도 씀
- `ssh_rule_ids`와 `ssh_allowed_cidrs`는 같은 키를 가짐(규칙 1개 = CIDR 1개)

A-2. `modules/network/variables.tf`

```hcl
# 모듈이 쓰는 키만 타입에 적음. 나머지 키(import id 등)는 변환 때 버려짐
variable "group_vars" {
  description = "network 그룹 값(local.group_vars.network)"
  type = object({
    ssh_allowed_cidrs = map(string) # 역할 키(ops_1, ops_2) → CIDR
  })
}

# 사설 대역 CIDR은 공개 가능한 값이라 root에서 직접 넘김
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "private_subnets" {
  description = "프라이빗 서브넷. 역할 키(a, c) → CIDR·가용 영역"
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
}
```

A-3. `modules/network/vpc.tf`

```hcl
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  lifecycle {
    prevent_destroy = true
  }
}

# vpc_id는 ID를 적지 않고 같은 모듈 자원 참조로 연결함
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
}
```

A-4. `modules/network/security_groups.tf`

```hcl
locals {
  # 예시 값. 실제 이름·설명과 같게 적음(다르면 교체됨)
  security_groups = {
    ssh = { name = "example-ssh", description = "example ssh" }
    rds = { name = "example-rds", description = "example rds" }
  }
}

# 인라인 ingress·egress 블록은 쓰지 않음. 규칙은 규칙별 리소스로 둠
resource "aws_security_group" "main" {
  for_each    = local.security_groups
  name        = each.value.name
  description = each.value.description
  vpc_id      = aws_vpc.main.id
}

# CIDR 1개당 규칙 1개. for_each 키는 역할 키이며 IP를 키로 쓰지 않음
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = var.group_vars.ssh_allowed_cidrs
  security_group_id = aws_security_group.main["ssh"].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}
```

- 자원 주소는 `module.network.aws_vpc_security_group_ingress_rule.ssh["ops_1"]` 형태로 PR CI 코멘트에 공개됨. CIDR 값은 그룹 값에서 오므로 코드에 남지 않음

A-5. `modules/network/outputs.tf`

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록(역할 키 순서)"
  value       = [for s in aws_subnet.private : s.id]
}

output "security_group_ids" {
  description = "보안 그룹 ID. 역할 키(ssh, rds 등) → ID"
  value       = { for k, sg in aws_security_group.main : k => sg.id }
}
```

A-6. `envs/prod/network.tf`

```hcl
module "network" {
  source = "../../modules/network"

  group_vars = local.group_vars.network

  vpc_cidr = "10.0.0.0/16" # 예시 값. 실제 CIDR과 같게
  private_subnets = {
    a = { cidr_block = "10.0.1.0/24", availability_zone = "ap-northeast-2a" }
    c = { cidr_block = "10.0.2.0/24", availability_zone = "ap-northeast-2c" }
  }
}
```

A-7. `envs/prod/imports_network.tf`

```hcl
import {
  to = module.network.aws_vpc.main
  id = local.group_vars.network.vpc_id
}

# 여러 개인 자원은 for_each로 씀. 키는 모듈의 for_each 키와 같아야 함
import {
  for_each = local.group_vars.network.private_subnet_ids
  to       = module.network.aws_subnet.private[each.key]
  id       = each.value
}

import {
  for_each = local.group_vars.network.security_group_ids
  to       = module.network.aws_security_group.main[each.key]
  id       = each.value
}

# 규칙 import id는 규칙 ID(sgr-...)
import {
  for_each = local.group_vars.network.ssh_rule_ids
  to       = module.network.aws_vpc_security_group_ingress_rule.ssh[each.key]
  id       = each.value
}
```

**B. 그룹 사이 값 전달(network → database)**

```hcl
# envs/prod/database.tf
module "database" {
  source = "../../modules/database"

  season = local.season

  # network output 참조. ID를 코드나 그룹 값에 다시 적지 않음
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.security_group_ids["rds"]
}
```

```hcl
# modules/database/variables.tf
variable "season" {
  description = "시즌 상태(local.season)"
  type = object({
    rds_multi_az = bool
  })
}

variable "subnet_ids" {
  description = "DB 서브넷 그룹에 넣을 서브넷 ID(module.network.private_subnet_ids)"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS 보안 그룹 ID(module.network.security_group_ids[\"rds\"])"
  type        = string
}
```

```hcl
# modules/database/main.tf
resource "aws_db_subnet_group" "main" {
  name       = "example-db-subnet-group" # 예시 값
  subnet_ids = var.subnet_ids
}

# 나머지 속성(엔진·스토리지·백업 창 등)은 생략. 실제 값과 같게 적음
resource "aws_db_instance" "main" {
  identifier     = "example-db"   # 예시 값
  instance_class = "db.t4g.micro" # 예시 값

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  multi_az               = var.season.rds_multi_az

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password]
  }
}
```

- 모듈 변수 타입에 `rds_multi_az`만 적으면 `local.season`의 나머지 속성은 변환 때 버려짐
- RDS 보안 그룹은 network가 import·관리하고 database는 output만 참조함. 같은 자원을 두 주소가 관리하지 않음
- 참조 방향은 network → database 한쪽만임

**C. cdn·obs의 us-east-1 provider 전달**

```hcl
# modules/cdn/versions.tf (obs도 같음)
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0.0, < 7.0.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
```

```hcl
# modules/cdn/main.tf: CloudFront viewer 인증서는 us-east-1에만 있음
data "aws_acm_certificate" "www" {
  provider = aws.us_east_1

  domain   = var.domain_name
  statuses = ["ISSUED"]
}
```

```hcl
# envs/prod/cdn.tf
module "cdn" {
  source = "../../modules/cdn"

  # 왼쪽: 모듈 안 이름, 오른쪽: providers.tf의 provider
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name = "www.example.com" # 예시 값
}
```

- `provider =`를 적지 않은 자원(CloudFront 배포·Route53)은 기본 provider(ap-northeast-2)를 씀

### 1-1. 자원 ID·IP를 코드 밖으로 빼는 규칙

공개 저장소이므로 자원 ID(VPC·서브넷·보안 그룹·인스턴스·CloudFront 배포·Route53 영역·AMI 등), 계정 ID가 들어간 ARN, 개인 IP는 `.tf` 파일에 적지 않음. `-generate-config-out` 초안에는 이 값이 그대로 들어가므로 아래 순서로 바꾼 뒤 옮김

1. **다른 자원 참조**: 같은 state의 자원 속성을 참조함. 예: 서브넷의 `vpc_id`는 `aws_vpc.main.id`(예시 A-3), 다른 그룹 자원은 그 그룹 모듈의 output(예시 B)
2. **data source 조회**: 참조할 자원이 없으면 이름·태그 기준 data source로 조회함. 예: 버킷 정책의 CloudFront 배포 ARN(`23-sto.md` STO-01-05), AMI는 `data "aws_ami"` 이름 필터, ACM 인증서(예시 C)
3. **그룹 값**: 위 두 가지로 없앨 수 없는 값(import 블록의 `id`, SSH 허용 CIDR 등)은 SSM String 파라미터 `/boaz/terraform/group-vars`(JSON 객체 하나)에 `<그룹>.<키>` 형태로 둠. 코드는 `local.group_vars.<그룹>.<키>`로 참조함(예시 A-1, A-7)
   - 로컬 plan과 PR CI 모두 같은 파라미터를 읽음. 그룹 값을 위한 별도 파일·GitHub secret은 없음(CI의 secret 3개는 backend·계정 ID용)
   - 읽기 전용 권한(`ssm:GetParameter`)으로 읽힘. String 유형이라 KMS 복호화가 필요 없음
   - 실제 값은 `docs/records/inventory.md` 또는 읽기 명령으로 확인함. 값을 저장소·PR·공개 채널에 적지 않음
   - 새 키 추가 절차(이 문서에서 이 절만 기준임)
     1. 그룹 담당: PR 본문에 추가한 키 이름(`<그룹>.<키>`)과 inventory.md의 참조 위치를 적고 이슈 코멘트로 관리자에게 갱신을 요청함
     2. 관리자: 현재 값을 읽어 키를 추가한 JSON 파일을 저장소 밖에 만들고 `aws ssm put-parameter --name /boaz/terraform/group-vars --type String --overwrite --value file://<파일>`로 덮어씀. 작업 후 JSON 파일을 지움
     3. 갱신은 그 키를 쓰는 PR 머지 전에 함. 갱신 전에는 그 PR의 plan이 키 누락("Unsupported attribute")으로 실패함. 코드가 아직 쓰지 않는 키는 plan에 영향이 없으므로 먼저 넣어 둬도 됨
   - 이전 값은 파라미터 이력(`aws ssm get-parameter-history`)으로 되돌림(관리자만)
   - Standard 등급이라 값 전체가 4KB를 넘을 수 없음. 넘을 것 같으면 STA 담당과 파라미터 분리를 정함
   - 파라미터 값은 plan 출력에 그대로 나타날 수 있음(sensitive 표시 없음). plan 원문을 공개 채널에 붙이지 않음

- `check-sensitive.sh`가 잡는 것은 계정 ID·IP·키 형태뿐임. 자원 ID 대부분은 걸리지 않으므로 PR 리뷰에서 직접 확인함(5절)

### 1-2. 그룹 값을 plan 때 읽어 오는 원리

1-1절 3번의 그룹 값은 data source로 읽음. data source는 state에 저장되지 않고 plan마다 AWS에서 새로 조회됨. 관리자가 파라미터를 고치면 다음 plan부터 로컬·PR CI 모두에 반영됨

```hcl
# envs/prod/locals.tf (요약)
data "aws_ssm_parameter" "group_vars" {
  name = "/boaz/terraform/group-vars"
}

locals {
  group_vars = jsondecode(data.aws_ssm_parameter.group_vars.insecure_value)
}
```

| 순서 | `terraform plan` 실행 때 일어나는 일 |
| --- | --- |
| 1 | `envs/prod/`의 모든 `.tf`를 읽음(`locals.tf`의 data 블록 포함) |
| 2 | AWS provider가 자격 증명을 정함. 로컬은 `AWS_PROFILE=boaz`, PR CI는 OIDC로 받은 plan 역할 |
| 3 | provider가 `ssm:GetParameter`로 파라미터 값을 가져옴 |
| 4 | JSON 문자열을 `jsondecode`로 객체로 바꿔 `local.group_vars`에 둠 |
| 5 | 그룹 코드의 `local.group_vars.<그룹>.<키>` 자리에 실제 값이 들어감 |
| 6 | 값이 채워진 설정을 state·실제 AWS와 비교해 plan 결과를 출력함 |

- `insecure_value`를 쓰는 이유: `value`는 sensitive로 표시되어 import `id`·`cidr_blocks`까지 sensitive가 전파됨. 이 파라미터는 시크릿이 아닌 String 유형임. SecureString이면 `insecure_value`가 비어 `locals.tf`의 검사(postcondition)가 "String 유형이어야 함" 오류로 plan을 중단함
- 테스트(`envs/prod/tests/season.tftest.hcl`)는 AWS에 요청하지 않는 mock provider로 실행되며 이 data source 값을 `{}`로 지정함
- **그룹 담당이 할 일**: PR CI의 Terraform Validate 작업이 `terraform test`(`season.tftest.hcl`)에서 실패하면 테스트 파일을 고치지 않고 STA 담당에게 요청함
  - 원인: 테스트는 그룹 값을 `{}`로 지정함. 첫 그룹이 그룹 값 키나 import 블록을 추가하면 키가 없어 실패함
  - STA 담당이 `season.tftest.hcl`에 자리 표시 키와 `override_resource`를 추가함

## 2. apply 순서 규칙

state 파일이 하나라서 한 번에 한 그룹만 apply함. apply는 관리자만 수행함(decisions.md "apply 실행 주체", "Phase 2 게이트 범위")

- `import-log.md`의 그룹 상태는 `대기` → `작업 중` → `apply 중` → `완료` 네 단계임
  - `작업 중`: 재조사·코드 작성·plan 맞추기·PR 리뷰. 여러 그룹이 동시에 있어도 됨
  - `apply 중`: 관리자가 머지·apply를 실행하는 동안. 동시에 `apply 중`인 그룹은 최대 1개
- apply는 `apply 중`으로 먼저 적은 그룹부터 함
- 머지·apply 순서(관리자)
  1. `import-log.md`에 `apply 중` 기록
  2. PR 머지
  3. `dev` 최신 커밋에서 `plan -out=plan.bin`
  4. 그 plan 파일로 로컬 게이트 실행(부록 A-1). 통과한 경우만 진행
  5. 같은 plan 파일로 apply
  6. 같은 커밋에서 다시 plan해 "No changes" 확인
- 머지 뒤 `dev`에서 apply하는 이유: 브랜치에서 apply하고 나중에 머지하면, 그 사이 다른 그룹의 plan에 이 그룹 자원이 코드에 없어 삭제로 나옴
- 로컬 게이트가 필수인 이유: PR CI의 게이트는 관리자가 실제로 apply하는 plan 파일을 검사하지 않음
- 안전 게이트(`scripts/plan_gate.py`)가 차단하는 것

| 규칙 | 차단 대상 |
| --- | --- |
| G1 | 보호 자원(RDS·EC2·EIP와 연결·CloudFront·Route53 레코드·영역·S3 버킷) 삭제·교체 |
| G2 | 시크릿 노출(RDS 비밀번호 변경, 시크릿을 state에 저장하는 설정, sensitive output) |
| G3 | `0.0.0.0/0`·`::/0`에서 80·443 외 포트를 여는 inbound 규칙 추가·변경 |
| G4 | Phase 2 동안 보호 자원 밖을 포함한 모든 자원의 삭제·교체 |

- 게이트는 신규 생성(create)·설정 변경(update)·import·`removed` 블록(forget)은 통과시킴. "그 그룹의 import와 승인된 변경만 있는지"는 사람이 plan 요약을 보고 확인함. 다른 그룹 자원의 변경이 하나라도 보이면 멈추고 `dev` 최신 상태부터 다시 확인함
- apply 대기가 겹치면 12월 전 마감이 걸린 두 순서를 먼저 apply함(decisions.md): ① STO-01 → CDN-02 1단계 → CDN-03(관리자 페이지 오픈), ② IAM-02 → CMP-01 → CMP-02(시즌 전환). 나머지(OBS·NET·IAM-03·RDB·DEP 등)는 그 사이에 apply함
- `apply 중`인 동안 다른 PR은 머지하지 않음
- `dev` 브랜치 보호는 적용 예정임. 적용 전까지 승인 1건·`Apply Ready` 통과·`apply 중` 동안 머지 금지는 GitHub가 강제하지 않으며 사람이 지키는 규칙임
- 기다리는 사람은 plan만 실행하며 코드를 맞춤. plan도 state 잠금을 잡으므로 `-lock-timeout=5m`을 붙임. `-lock=false`는 쓰지 않음
- 잠금이 오래 풀리지 않으면 잠금을 잡은 사람에게 먼저 확인함. 강제 해제·state 복구는 관리자만 아래 순서로 수행함
  1. 오류 메시지의 Lock ID·Who·Created 확인
  2. 잠금을 잡은 사람에게 연락해 terraform 프로세스 종료 확인
  3. `import-log.md`에 해제 사유·Lock ID·시각 기록
  4. `terraform -chdir=envs/prod force-unlock <Lock ID>`
  5. 바로 `terraform -chdir=envs/prod plan -input=false`로 state 확인. 이상하면 state 버킷의 이전 버전으로 복구하고 리뷰 요청

## 3. 작업 순서

| 단계 | 할 일 | 완료 확인 방법 |
| --- | --- | --- |
| 1. 착수 선언 | `import-log.md`에 상태 `작업 중`, 담당 역할, 시작 시각을 적어 작은 PR로 올림. 브랜치 `feat/import-<그룹>`을 `dev`에서 만듦 | import-log.md 해당 행 갱신 |
| 2. 직전 재조사 | 그 그룹 자원만 AWS CLI 읽기 명령으로 다시 조사해 `inventory.md` 갱신. 시크릿 값은 조회하지 않음 | inventory 갱신 시각이 착수 이후 |
| 3. 코드 작성 | `-generate-config-out`으로 초안을 만들고(부록 A-2), 1-1절 규칙대로 ID·ARN·IP를 바꿔 `modules/<그룹>/`로 옮김. import 블록의 `to`를 `module.<그룹>.<자원>`으로 바꿈. `generated.tf`는 삭제. obs는 import 없이 명세대로 새 자원을 작성함 | `validate` 통과, `.tf`에 자원 ID·IP 없음 |
| 4. 보호 설정 | 보호 대상 자원에 `prevent_destroy` 추가. 재생성을 일으키는 속성은 실제 값과 똑같이 맞춤 | 코드에 `prevent_destroy` 존재 |
| 5. plan 맞추기 | `git merge origin/dev`로 최신 `dev`를 반영한 뒤 로컬 plan(부록 A-1). 차이가 0이 될 때까지 코드 수정. 삭제·교체가 나오면 즉시 멈춤(4절) | import만 있고 변경·교체·삭제 0건(예외는 아래) |
| 6. PR | base `dev`, 제목 `[Feat] network 그룹 import` 형식, PR 템플릿 작성. plan 결과는 PR CI 요약 코멘트로 대체하고 plan 원문은 붙이지 않음. 새 그룹 값 키가 있으면 1-1절 3번 절차로 요청. 리뷰 1명 이상 승인 | 승인 1건 이상, `Apply Ready` 통과 |
| 7. 머지·apply | 이슈 코멘트로 관리자에게 apply 요청. 관리자가 2절 순서로 머지·apply | 로컬 게이트 통과, apply 결과가 5단계 기준과 같음 |
| 8. 최종 확인 | `dev` 같은 커밋에서 다시 plan | 출력에 "No changes." |
| 9. 기록 | `import-log.md`에 대상 자원, plan 결과 문구, 남은 차이, 관리 제외 항목과 사유 기록. 상태 `완료`(작은 PR) | import-log.md 해당 행 갱신 |

- 완료 기준 예외(5·7단계)
  - obs(OBS-01): 기존 자원 import가 없음. plan에 신규 생성(create)만 있고 변경·교체·삭제 0건
  - CDN-03: import된 CloudFront의 설정 변경. plan에 명세서가 정한 설정 변경(update)만 있고 교체·삭제 0건. PR 본문에 변경 항목을 적고 리뷰 승인을 받음
  - CDN-03-01(WAF 규칙)은 코드가 아니라 콘솔로 적용하고 decisions.md에 기록함(WebACL은 참조만 하는 결정). 이 항목은 plan에 나오지 않음
  - 두 경우 모두 apply 뒤 8단계 "No changes."는 같게 적용함
- 로컬 plan과 PR CI plan의 차이
  - PR CI는 PR 브랜치를 그 시점 `dev`에 합친 결과(`refs/pull/<번호>/merge`)로 plan함. 코멘트의 "커밋 xxx"는 브랜치 최신 커밋이지만 plan 대상은 합친 결과임
  - 로컬 plan은 현재 브랜치 그대로 plan함. 브랜치가 오래되면 그 사이 apply된 다른 그룹 자원이 삭제로 나옴. 5단계에서 `dev`를 먼저 합쳐 이를 막음
  - `dev`가 바뀐 뒤 CI plan을 다시 보려면 Actions에서 workflow를 다시 실행함
- PR CI 작업과 실패 시 할 일

| 작업 | 실패 시 할 일 |
| --- | --- |
| Sensitive Info Check, Gitleaks | 값을 지우고 커밋을 다시 만듦. 우회하지 않음 |
| Terraform Format | `terraform fmt -recursive` 후 커밋 |
| Terraform Validate | 로컬 validate·test 재현(부록 A-3). 테스트 mock 문제면 STA 담당에게 요청(1-2절) |
| TFLint | 부록 A-3 명령으로 재현해 수정 |
| Python Tests | 부록 A-3 명령으로 재현 |
| Terraform Plan (envs/prod) | PR 코멘트의 사유 확인. 게이트 차단이면 4절 |
| Apply Ready | 위 작업이 모두 성공해야 통과함 |

## 4. 멈춰야 하는 경우

아래 중 하나라도 해당하면 작업·머지·apply를 멈춤

- plan에 어떤 자원이든 삭제(delete)·교체(replace)가 나온 경우. 보호 자원이 아니어도 Phase 2 동안은 G4로 차단됨
- 안전 게이트가 PR CI나 로컬에서 실패한 경우
- 로컬 plan에 다른 그룹 자원의 변경이 나온 경우(`dev`를 합친 뒤에도 남을 때)
- plan 출력에 비밀번호·시크릿 값이 보이는 경우. 출력을 어디에도 붙이지 않음
- 시크릿을 조회해야만 진행되는 경우
- 조사로 확정되지 않은 식별자를 써야 하는 경우(추정값 사용 금지)
- 12월 시즌 동결 기간(2026-12-07부터 season-down 후 3일까지)이거나 2027-01 앱 릴리스 월인 경우(OPS 명세서)

멈추면 PR(PR이 없으면 티켓 이슈)에 상황을 적고 STA 담당·관리자·해당 그룹 담당이 함께 확인함. plan 원문 대신 PR CI 요약 코멘트의 자원 주소와 사유만 적음

## 5. 그룹 PR 리뷰 체크리스트

리뷰어는 아래 항목을 모두 확인한 뒤 승인함

- [ ] 수정 파일이 자기 그룹 파일(1절 표)과 `inventory.md`의 자기 그룹 부분뿐
- [ ] 착수 기록(`import-log.md` `작업 중`)이 `dev`에 있음. `완료` 기록은 apply 뒤 작은 PR로 올림
- [ ] PR CI plan 요약에 변경·교체·삭제가 0건(obs는 create만, CDN-03은 명세의 update만). 다른 그룹 자원이 나오지 않음(나오면 `dev` 변경 뒤 workflow 재실행 요청)
- [ ] 보호 대상 자원에 `prevent_destroy`가 있음
- [ ] 코드에 시크릿 값, 계정 ID, 개인 IP, 자원 ID(`vpc-`·`subnet-`·`sg-`·`sgr-`·`i-`·`ami-`·CloudFront 배포 ID·Route53 영역 ID 등)가 없음. 자원 이름·`for_each` 키에도 없음
- [ ] PR 본문에 plan 원문이 붙어 있지 않음
- [ ] 새 그룹 값 키가 있으면 본문에 키 이름이 있고 파라미터가 갱신됨(1-1절 3번)
- [ ] 명세서의 그룹 고유 기능이 모두 반영됨

---

## 부록 A. 명령 모음

모든 명령은 저장소 루트에서 실행함. 모듈 폴더에서는 init·plan을 실행하지 않음. `-chdir`를 쓰면 `-out=plan.bin`·`-backend-config=backend.hcl`은 `envs/prod/` 기준 경로임

### A-1. plan과 로컬 게이트

```bash
export AWS_PROFILE=boaz
git fetch origin && git merge origin/dev   # 로컬 plan 전 최신 dev 반영(3절 5단계)

# 최초 1회, module 블록을 추가·변경한 뒤에도 다시 실행
terraform -chdir=envs/prod init -input=false -lockfile=readonly -backend-config=backend.hcl

terraform -chdir=envs/prod validate
terraform -chdir=envs/prod plan -input=false -lock-timeout=5m -out=plan.bin

# 로컬 게이트. plan JSON에는 값이 평문으로 들어가므로 저장소 밖에 두고 확인 뒤 지움
terraform -chdir=envs/prod show -json plan.bin > /tmp/plan.json
python3 scripts/plan_gate.py /tmp/plan.json   # 위반 있으면 exit 1
rm -f /tmp/plan.json envs/prod/plan.bin
```

- 관리자는 apply 직전에 apply할 plan 파일로 이 게이트를 반드시 실행함(2절)

### A-2. 코드 초안 생성(`-generate-config-out`)

초안 생성에는 두 가지 제한이 있음

- root 주소만 됨. 모듈 주소(`module.network.…`)는 "Only resources within the root module are eligible for config generation" 오류
- `for_each` import는 안 됨. "The target resource does not use for_each" 오류. 여러 개인 자원도 import 블록을 하나씩 먼저 씀

1) `imports_network.tf`에 root 주소로 임시 작성

```hcl
import {
  to = aws_vpc.main
  id = local.group_vars.network.vpc_id
}

import {
  to = aws_subnet.private_a
  id = local.group_vars.network.private_subnet_ids.a
}
```

2) 초안 생성

```bash
terraform -chdir=envs/prod plan -input=false -generate-config-out=generated.tf
```

3) `envs/prod/generated.tf`의 자원을 `modules/network/`로 옮김
   - ID·ARN·IP를 참조·data source·그룹 값으로 바꿈(1-1절)
   - 보안 그룹의 인라인 `ingress`·`egress`는 지우고 규칙별 리소스로 옮김
   - 하나씩 생성한 자원(`private_a`, `private_c`)은 `for_each` 자원 하나(`aws_subnet.private`)로 합침
4) 임시 import 블록을 예시 A-7 형태(`to = module.network.…`, 필요하면 `for_each`)로 바꿈
5) `generated.tf` 삭제 후 다시 확인

```bash
rm envs/prod/generated.tf
terraform -chdir=envs/prod init -input=false -lockfile=readonly -backend-config=backend.hcl
terraform -chdir=envs/prod validate
terraform -chdir=envs/prod plan -input=false -lock-timeout=5m
```

### A-3. 커밋 전 로컬 검사(자격 증명 불필요)

```bash
terraform fmt -recursive
bash scripts/check-sensitive.sh

# CI와 같은 validate·test. 이미 S3 backend로 init한 .terraform/과 섞이지 않게 데이터 디렉터리를 따로 씀
export TF_DATA_DIR=/tmp/tf-validate
terraform -chdir=envs/prod init -backend=false -input=false -lockfile=readonly
terraform -chdir=envs/prod validate
terraform -chdir=envs/prod test
unset TF_DATA_DIR

tflint --init --config "$PWD/.tflint.hcl" && tflint --recursive --config "$PWD/.tflint.hcl"

# Python 테스트. 가상 환경은 저장소 밖에 둠(.venv/는 gitignore 대상이 아님)
python3.12 -m venv ~/.venvs/boaz-infra
~/.venvs/boaz-infra/bin/pip install --require-hashes --no-deps -r tests/requirements.txt
HYPOTHESIS_PROFILE=ci ~/.venvs/boaz-infra/bin/python -m pytest
```

## 부록 B. 자주 묻는 질문

| 질문 | 답 |
| --- | --- |
| apply·그룹 값 갱신·잠금 해제는 어디에 요청하나 | 해당 티켓의 GitHub 이슈 코멘트로 관리자(Admin 그룹 운영진)에게 요청함 |
| 로컬 plan에는 다른 그룹 삭제가 나오는데 CI plan은 깨끗함 | 브랜치가 오래된 것임. `git merge origin/dev` 후 다시 plan함(3절) |
| CI plan에만 다른 그룹 자원이 나옴 | `dev`에 다른 그룹 머지가 들어온 뒤 apply 전일 수 있음. 관리자에게 확인하고 workflow를 다시 실행함 |
| plan이 "Unsupported attribute"로 멈춤 | 그룹 값 파라미터에 키가 없음. 1-1절 3번 절차로 요청함 |
| init이 잠금 파일 때문에 실패함 | 새 provider가 필요한 경우임. STA 담당에게 잠금 파일 갱신을 요청함(1-0-1절) |
| Terraform Validate의 `terraform test`만 실패함 | 그룹 값 mock 문제일 수 있음. STA 담당에게 요청함(1-2절) |
| plan이 잠금을 못 얻음 | `-lock-timeout=5m`으로 다시 실행함. 계속되면 2절 순서로 관리자에게 요청함 |
| `aws login`이 안 됨 | 읽기 전용 그룹에는 권한이 없음. 액세스 키 방식(0-1절)을 씀 |
