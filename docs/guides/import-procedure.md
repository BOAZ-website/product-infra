# 그룹 import 공통 절차

기준일 2026-09-26 · Phase 2 1차·2차의 모든 import 티켓(NET-01, IAM-02, IAM-03, STO-01, CMP-01, CMP-02, RDB-01, CDN-02, DEP-02)에 적용

> 각 명세서에는 그 그룹에만 해당하는 항목만 적음. 이 페이지의 절차는 모든 그룹이 똑같이 따름
> 시작 조건: STA-07(안전 게이트) 완료. 이전에는 어떤 그룹도 import를 시작하지 않음
> 게이트는 PR CI plan 작업에서 자동으로 돎(`scripts/plan_gate.py`). Phase 2 동안은 보호 자원 밖 자원의 삭제·교체도 차단함(G4). 관리자는 apply 직전에 apply할 plan 파일로 반드시 로컬에서 다시 실행함(2절). 로컬에서 미리 확인: `terraform -chdir=envs/prod plan -out=plan.bin` → `terraform -chdir=envs/prod show -json plan.bin > /tmp/plan.json` → `python3 scripts/plan_gate.py /tmp/plan.json`(plan JSON에는 값이 평문으로 들어가므로 저장소 안에 두지 않고 확인 뒤 지움)

---

## 0. 로컬 준비

그룹 작업을 시작하기 전 한 번만 함. 아래 생성 파일(`backend.hcl`, `terraform.tfvars`, 자격 증명)은 모두 저장소에 커밋하지 않음

### 0-1. AWS 계정과 자격 증명

- 팀원은 인프라 리드가 만든 IAM 사용자로 접근함. 콘솔 초기 비밀번호는 비공개 채널로 1회 전달받고 **첫 로그인 시 바로 변경**함
- 권한은 두 가지임(결정 레지스터 "팀원 권한 범위 / apply 실행 주체")
  - **관리자(Admin 그룹)**: 재조사·plan·apply 모두 가능. `apply`는 관리자만 수행하며 한 번에 한 그룹만
  - **읽기 전용(`terraform-readonly` 그룹: 모든 조회 + state 접근)**: import 재조사와 `plan`은 되지만 자원 생성·변경·`apply`는 안 됨. apply가 필요하면 관리자에게 요청
- CLI로 `terraform plan`을 돌리려면 **콘솔 로그인만으로는 안 되고 CLI 자격 증명이 필요함.** 아래 중 하나:
  - **(A) `aws login`(권장)**: `aws login --profile boaz` → 브라우저로 콘솔 로그인 → 임시 세션이 프로필에 들어옴. 장기 키를 파일에 저장하지 않고 세션은 몇 시간 뒤 만료됨. 만료되면 다시 `aws login`
  - **(B) 액세스 키**: 콘솔 IAM → 본인 사용자 → 보안 자격 증명 → 액세스 키 생성 → `aws configure --profile boaz`로 등록. 장기 키라 `~/.aws/credentials`에 평문 저장되므로 **절대 커밋하지 않음**(이 저장소 보안 규칙). 공유 금지, 안 쓰면 비활성화
- 어느 방식이든 명령에 프로필을 붙임: `aws --profile boaz ...`, Terraform은 `AWS_PROFILE=boaz`를 export하거나 provider 프로필로 지정
- 시크릿은 조회하지 않음(권한도 막혀 있음): `kms:Decrypt`, `secretsmanager:GetSecretValue`, SecureString 복호화, S3 객체 내용(state 제외)은 거부됨. import 재조사에는 필요 없음(설정·타입은 `describe-*`로 조회)

### 0-2. 작업 파일 준비

| 순서 | 할 일 | 완료 확인 방법 |
| --- | --- | --- |
| 1 | `envs/prod/backend.hcl.example`을 `backend.hcl`로, `terraform.tfvars.example`을 `terraform.tfvars`로 복사하고 `docs/records/inventory.md`의 state 버킷 이름·계정 ID로 채움 | 두 파일 존재, `git status`에 나타나지 않음 |
| 2 | 운영 계정 자격 증명인지 확인: `aws --profile boaz sts get-caller-identity`의 Account가 inventory.md의 계정 ID와 같음 | Account 일치 |
| 3 | `terraform -chdir=envs/prod init -input=false -backend-config=backend.hcl` | `Successfully configured the backend "s3"!` |
| 4 | `terraform -chdir=envs/prod plan -input=false` | 오류 없이 plan 완료 |

- 계정 가드: provider와 backend 모두 `allowed_account_ids`가 있어 다른 계정 자격 증명이면 init·plan 단계에서 실패함
- workspace는 쓰지 않음(`terraform workspace new` 금지). workspace를 쓰면 state가 `env:/` 경로로 갈라짐
- plan·apply에는 항상 `-input=false`를 붙임. 변수 파일이 없을 때 입력을 기다리지 않고 바로 실패함
- state 잠금 파일(`.tflock`)은 읽기 전용 권한으로도 쓸 수 있음. `-lock=false`로 잠금을 피하지 않음(동시 작업 충돌 위험)
- CI와 같은 자격 증명 없는 검증(`init -backend=false` → `validate`)을 로컬에서 돌릴 때, 이미 S3 backend로 init한 `.terraform/`이 있으면 계정 가드에 걸려 실패함. 데이터 디렉터리를 바꿔 실행함: `TF_DATA_DIR=/tmp/tf-validate terraform -chdir=envs/prod init -backend=false -input=false -lockfile=readonly`
- `tests/`의 Python 테스트는 시스템 Python으로 돌리면 `hypothesis`가 없어 실패함. `python3 -m venv .venv && .venv/bin/pip install -r tests/requirements.txt` 뒤 `.venv/bin/pytest tests/`로 실행함(`.venv/`는 커밋하지 않음)

## 1. 파일 규칙

그룹마다 자기 파일만 수정함. 다른 그룹 파일을 고쳐야 하면 그 그룹 담당자에게 요청함

| 그룹 | 모듈 폴더 | envs/prod 파일 | import 블록 파일 | 명세서 |
| --- | --- | --- | --- | --- |
| obs | `modules/obs/` | `envs/prod/obs.tf` | 없음(기존 자원 import 없이 새로 만듦) | OBS |
| network | `modules/network/` | `envs/prod/network.tf` | `envs/prod/imports_network.tf` | NET |
| iam | `modules/iam/` | `envs/prod/iam.tf` | `envs/prod/imports_iam.tf` | IAM |
| params | `modules/params/` | `envs/prod/params.tf` | `envs/prod/imports_params.tf` | IAM |
| storage | `modules/storage/` | `envs/prod/storage.tf` | `envs/prod/imports_storage.tf` | STO |
| compute | `modules/compute/` | `envs/prod/compute.tf` | `envs/prod/imports_compute.tf` | CMP |
| database | `modules/database/` | `envs/prod/database.tf` | `envs/prod/imports_database.tf` | RDB |
| cdn | `modules/cdn/` | `envs/prod/cdn.tf` | `envs/prod/imports_cdn.tf` | CDN |
| deploy | `modules/deploy/` | `envs/prod/deploy.tf` | `envs/prod/imports_deploy.tf` | DEP |

- import 블록 파일은 `envs/prod/imports_<그룹>.tf`(평면 파일). Terraform은 root 모듈 디렉터리 바로 아래 `.tf`만 읽으므로 `imports/` 같은 하위 폴더에 두면 import 블록이 무시됨
- 그룹 파일(`envs/prod/<그룹>.tf`)에는 `module "<그룹>"` 호출과 그룹 전용 variable·locals만 둠. resource·data는 `modules/<그룹>/`에 작성
- 공통 파일(`envs/prod/versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `season.auto.tfvars`)은 STA 담당만 수정함
- 시즌에 따라 상태가 달라지는 자원(compute·database·cdn 그룹)은 `var.season_capacity`·`var.api_origin`을 직접 쓰지 않고 `local.season`(`envs/prod/locals.tf`)을 모듈 입력으로 넘겨받음. 시즌 값은 `season.auto.tfvars`가 자동으로 넘기므로 plan 때 따로 입력하지 않음
- 그룹 간 값 전달(예: network의 서브넷 ID를 database가 사용)은 상대 그룹 모듈의 output을 참조함. 필요한 output이 없으면 해당 그룹 담당자에게 추가를 요청함
- 두 그룹이 서로의 output을 참조하면 순환 참조가 됨. 한쪽은 data source로 조회함(예: storage 버킷 정책의 CloudFront 배포 ARN, `23-sto.md` STO-01-05)
- import가 끝나 state에 등록된 뒤에는 `envs/prod/imports_<그룹>.tf`의 import 블록을 지워도 됨. 지우는 것은 plan "No changes" 확인 후 별도 커밋으로 함
- us-east-1 자원(ACM 인증서, WAF WebACL 조회)을 다루는 모듈(cdn)은 모듈 안에서 `terraform { required_providers { aws = { source = "hashicorp/aws", configuration_aliases = [aws.us_east_1] } } }`로 별칭을 선언함. 그룹 파일의 `module "cdn"` 호출에는 `providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`를 넘김. 별칭 provider 자체는 `providers.tf`에 이미 있음

### 1-1. 자원 ID·IP를 코드 밖으로 빼는 규칙

공개 저장소이므로 자원 ID(VPC·서브넷·보안 그룹·인스턴스·CloudFront 배포·Route53 영역·AMI 등), 계정 ID가 들어간 ARN, 개인 IP는 `.tf` 파일에 적지 않음. `terraform plan -generate-config-out` 초안에는 이 값이 그대로 들어가므로 아래 순서로 바꾼 뒤 옮김

1. **다른 자원 참조**: 같은 state에 있는 자원의 속성을 참조함. 예: 서브넷의 `vpc_id`는 `aws_vpc.main.id`, 다른 그룹 자원은 그 그룹 모듈의 output
2. **data source 조회**: 참조할 자원이 없으면 이름·태그 기준 data source로 조회함. 예: 버킷 정책의 CloudFront 배포 ARN(`23-sto.md` STO-01-05), AMI는 `data "aws_ami"`에 이름 필터
3. **그룹 값**: 위 두 가지로 없앨 수 없는 값(import 블록의 `id`, SSH 허용 CIDR 등)은 SSM String 파라미터 `/boaz/terraform/group-vars`(JSON 객체 하나)에 `<그룹>.<키>` 형태로 둠. 코드는 `local.group_vars.<그룹>.<키>`로 참조함(`envs/prod/locals.tf`가 plan 때 이 파라미터를 직접 읽음)
   - 예: `{"network": {"ssh_allowed_cidrs": [...]}, "compute": {...}}`의 값을 `local.group_vars.network.ssh_allowed_cidrs`로 씀
   - 로컬 plan·PR CI 모두 별도 파일·secret 없이 같은 파라미터를 읽음. 읽기 전용 권한(`ssm:GetParameter`)으로 충분하고, String 유형이라 KMS 복호화가 필요 없음
   - 실제 값은 `docs/records/inventory.md` 또는 읽기 명령으로 조회함. 값을 저장소·PR·공개 채널에 적지 않음
   - 새 키를 쓰는 PR: 본문에 추가한 키 이름(`<그룹>.<키>`)과 inventory.md의 참조 위치를 적고 관리자(인프라 리드)에게 파라미터 갱신을 요청함. 읽기 전용 팀원은 파라미터를 바꿀 수 없음. 갱신 전까지 그 PR의 plan은 키 누락으로 실패함
   - 관리자의 갱신: 현재 값을 읽어 키를 추가한 JSON 파일을 저장소 밖에 만든 뒤 `aws ssm put-parameter --name /boaz/terraform/group-vars --type String --overwrite --value file://<파일>`로 덮어씀. 그 키를 쓰는 PR이 머지되기 **전에** 갱신함. 아직 코드가 쓰지 않는 키가 들어 있어도 plan에 영향 없으므로 먼저 넣어 둬도 됨. 작업 후 JSON 파일은 지움
   - 이전 값은 파라미터 이력(`aws ssm get-parameter-history`)으로 되돌릴 수 있음(관리자만)
   - Standard 등급이라 값 전체가 4KB를 넘을 수 없음. 넘을 것 같으면 STA 담당과 파라미터 분리를 정함
   - 파라미터 값은 plan 출력에 그대로 나타날 수 있음(sensitive 표시 없음). plan 원문을 공개 채널에 붙이지 않는 기존 규칙을 그대로 따름

- `check-sensitive.sh`가 잡는 것은 계정 ID·IP·키 형태뿐임. 자원 ID 대부분은 걸리지 않으므로 PR 리뷰에서 직접 확인함(5절 체크리스트)

### 1-2. 그룹 값을 plan 때 읽어 오는 원리

1-1절 3번의 그룹 값은 Terraform의 data source로 읽음. data source는 state에 저장되는 값이 아니며 plan 실행마다 AWS에서 새로 조회하는 값임. 관리자가 파라미터를 수정하면 다음 plan부터 로컬·PR CI 전체에 반영됨

```hcl
# envs/prod/locals.tf (요약)
data "aws_ssm_parameter" "group_vars" {
  name = "/boaz/terraform/group-vars"
}

locals {
  group_vars = jsondecode(data.aws_ssm_parameter.group_vars.insecure_value)
}

# 그룹 코드에서 사용(예)
#   cidr_blocks = local.group_vars.network.ssh_allowed_cidrs
```

`terraform plan` 실행 시 순서

| 순서 | 일어나는 일 |
| --- | --- |
| 1 | `envs/prod/`의 모든 `.tf` 파일을 읽음. `locals.tf`의 data 블록도 포함 |
| 2 | AWS provider가 요청에 쓸 자격 증명을 정함. 로컬은 0-1절 프로필(`AWS_PROFILE`), PR CI는 OIDC로 받은 plan 역할 |
| 3 | provider가 AWS API `ssm:GetParameter`로 `/boaz/terraform/group-vars` 값을 가져옴. `aws ssm get-parameter`와 같은 요청을 Terraform이 대신 보냄 |
| 4 | 가져온 JSON 문자열을 `jsondecode`로 객체로 바꿔 `local.group_vars`에 둠 |
| 5 | 그룹 코드의 `local.group_vars.<그룹>.<키>` 자리에 실제 값이 들어감 |
| 6 | 이 값을 넣은 설정을 state·실제 AWS와 비교해 plan 결과를 냄 |

- `insecure_value`를 쓰는 이유: `value`는 sensitive로 표시되어 import 블록 `id`·`cidr_blocks`까지 sensitive가 전파됨. 이 파라미터는 시크릿이 아닌 String 유형이므로 `insecure_value`로 읽음. 파라미터가 SecureString이면 `insecure_value`가 비어 있음. 이 경우 `locals.tf`의 검사(postcondition)가 "String 유형이어야 함" 오류를 내고 plan을 중단함
- 키가 파라미터에 없으면 그 키를 쓰는 코드의 plan이 오류로 중단됨. 키를 먼저 추가하고 코드를 나중에 머지함(1-1절 3번)
- 테스트(`envs/prod/tests/season.tftest.hcl`)는 AWS에 요청하지 않는 모의(mock) provider로 실행됨. 이 data source 값은 `{}`로 지정함
- 같은 원리를 쓰는 기존 사례: 버킷 정책의 CloudFront 배포 ARN 조회(STO-01-05), AMI 이름 조회
- 그룹 값은 이 원리를 "코드에 적을 수 없고 이름으로 찾을 수도 없는 값"에 적용한 사례임

## 2. apply 순서 규칙

state 파일은 하나라서 한 번에 한 사람만 apply할 수 있음

- `import-log.md`의 그룹 상태는 `대기` → `작업 중` → `apply 중` → `완료` 네 단계임
  - `작업 중`: 재조사·코드 작성·plan 맞추기·PR 리뷰. 여러 그룹이 동시에 있어도 됨(1차 시작 시 8개 파트 동시 착수)
  - `apply 중`: PR 승인 뒤 관리자가 apply를 실행하는 동안. **동시에 `apply 중`인 그룹은 최대 1개**
- apply는 `apply 중`으로 먼저 적은 그룹부터 함. 읽기 전용 팀원은 apply 권한이 없으므로 관리자(인프라 리드)에게 요청함
- **머지 뒤 `dev`에서 apply**: apply는 PR 브랜치가 아니라 PR을 머지한 `dev` 최신 커밋에서 함. 브랜치에서 apply하고 나중에 머지하면, 그 사이 다른 그룹의 plan에서 이 그룹 자원이 코드에 없어 삭제(destroy)로 나옴. 순서는 `apply 중` 기록 → PR 머지 → `dev` 최신에서 plan → 게이트 검사 → 같은 plan 파일로 apply → 최종 확인. `apply 중`인 동안 다른 PR은 머지하지 않음
- **apply 전 로컬 게이트 필수**: PR CI의 게이트는 실제로 apply하는 plan 파일을 검사하지 않음. 관리자는 apply할 그 plan 파일로 `terraform -chdir=envs/prod show -json plan.bin > /tmp/plan.json && python3 scripts/plan_gate.py /tmp/plan.json`을 실행해 통과한 경우에만 apply함. 확인 뒤 `/tmp/plan.json`은 지움(값이 평문으로 들어 있음)
- plan에 **해당 그룹의 import와 변경만** 있을 때만 apply함. 다른 그룹 자원의 삭제·변경이 하나라도 보이면 멈추고 `dev` 최신 상태부터 다시 확인함
- apply 대기가 겹치면 12월 전 마감이 걸린 두 선행 순서를 먼저 apply함: ① STO-01 → CDN-02 1단계 → CDN-03(관리자 페이지 오픈), ② IAM-02 → CMP-01 → CMP-02(시즌 전환). 나머지 그룹(OBS·NET·IAM-03·RDB·DEP 등)은 그 사이에 apply함
- 기다리는 사람은 `terraform plan`만 실행하며 코드를 맞춤. plan도 state 잠금을 잡으므로 동시에 실행하면 한쪽이 잠금을 못 얻어 실패할 수 있음. `terraform plan -lock-timeout=5m`처럼 잠금 대기 시간을 주고, 잠금을 끄는 옵션(`-lock=false`)은 쓰지 않음
- 잠금이 오래 풀리지 않으면 강제 해제(`force-unlock`)하지 말고 잠금을 잡은 사람에게 먼저 확인함
- 강제 해제가 꼭 필요할 때만 아래 순서를 따름
  1. 오류 메시지의 Lock ID·Who·Created 확인
  2. 잠금을 잡은 사람에게 연락해 해당 terraform 프로세스가 종료됐는지 확인
  3. `import-log.md`에 해제 사유·Lock ID·시각 기록
  4. `terraform -chdir=envs/prod force-unlock <Lock ID>`
  5. 바로 `terraform plan -input=false`로 state가 정상인지 확인. 이상하면 state 버킷의 이전 버전으로 복구하고 리뷰 요청

## 3. 작업 순서

| 단계 | 할 일 | 완료 확인 방법 |
| --- | --- | --- |
| 1. 착수 선언 | `import-log.md`에 그룹 상태 `작업 중`, 담당자, 시작 시각 기록(이 갱신은 작은 PR로 따로 올림. 여러 그룹이 같은 표를 고치므로 코드 PR에 섞으면 충돌이 생김). 브랜치 `feat/import-<그룹>` 생성. 커밋 메시지는 `type: 설명 (#해당 티켓 이슈 번호)` 형식이어야 훅을 통과함 | import-log.md 해당 행 갱신 |
| 2. 직전 재조사 | 그 그룹 자원만 AWS CLI 읽기 명령으로 다시 조사해 inventory.md 갱신. 시크릿 값은 조회하지 않음 | inventory 갱신 시각이 착수 이후 |
| 3. 코드 작성 | import 블록을 root 주소(예: `aws_vpc.main`)로 먼저 쓰고 `terraform plan -generate-config-out=generated.tf`로 코드 초안 생성(초안 생성은 root 주소만 지원). 초안의 자원 ID·ARN·IP를 1-1절 규칙대로 참조·data source·변수로 바꾸고 `modules/<그룹>/`으로 옮긴 뒤, import 블록의 `to`를 `module.<그룹>.<자원>`으로 바꿈. `generated.tf`는 커밋하지 않고 삭제 | `terraform validate` 통과, `.tf`에 자원 ID·IP 없음 |
| 4. 보호 설정 | 보호 대상 자원에 `prevent_destroy` 추가. 재생성을 일으키는 속성은 실제 값과 똑같이 맞춤 | 코드에 `prevent_destroy` 존재 |
| 5. plan 맞추기 | `terraform plan`에서 차이가 0이 될 때까지 코드 수정. 교체·삭제가 나오면 즉시 멈추고 리뷰 요청 | plan 결과에 import만 있고 변경·교체·삭제 0건 |
| 6. PR | PR 템플릿 작성. plan 결과는 PR CI가 다는 요약 코멘트로 대체함. **plan 원문은 붙이지 않음**(자원 ID·IP가 들어 있음). 새 변수를 만들었으면 본문에 적고 STA 담당에게 CI secret 갱신 요청(1-1절). 리뷰 1명 이상 승인 | PR에 승인 1건 이상, `Apply Ready` 통과 |
| 7. 머지·apply | 관리자에게 apply 요청. 관리자가 `import-log.md` 상태를 `apply 중`으로 바꾸고 PR 머지 → `dev` 최신에서 `plan -out=plan.bin` → 로컬 게이트 통과 확인 → 같은 plan 파일로 apply(state 등록만 일어남). 2절 "머지 뒤 dev에서 apply" 참조 | 게이트 통과, apply 로그에 `import`만 존재 |
| 8. 최종 확인 | `dev` 같은 커밋에서 다시 `terraform plan` | 출력에 "No changes." 문구 |
| 9. 기록 | `import-log.md`에 대상 자원, plan 결과 문구, 남은 차이, 관리 제외 항목과 사유 기록. 그룹 상태 `완료`(이 갱신은 작은 PR로 올림) | import-log.md 해당 행 갱신 |

## 4. 멈춰야 하는 경우

- plan에 보호 자원(RDS, EC2, EIP, CloudFront, Route53, S3)의 교체(replace)나 삭제(delete)가 나온 경우
- 조사로 확정되지 않은 식별자를 써야 하는 경우(추정값 사용 금지)
- plan 출력에 비밀번호·시크릿 값이 보이는 경우
- 12월 시즌 동결 기간이거나 2027-01 앱 릴리스 월인 경우(→ OPS 명세서 참조)

멈춘 경우 PR에 상황을 적고 STA 담당과 해당 그룹 담당이 함께 확인함

## 5. 그룹 PR 리뷰 체크리스트

리뷰어는 아래 항목을 모두 확인한 뒤 승인함

- [ ] 수정 파일이 자기 그룹 파일(1절 표)뿐
- [ ] plan 결과에 변경·교체·삭제가 0건. 다른 그룹 자원이 plan에 나오지 않음(나오면 `dev` 최신으로 맞춘 뒤 다시 plan 요청)
- [ ] 보호 대상 자원에 `prevent_destroy`가 있음
- [ ] 코드에 시크릿 값, 계정 ID, 개인 IP, 자원 ID(`vpc-`·`subnet-`·`sg-`·`i-`·`ami-`·CloudFront 배포 ID·Route53 영역 ID 등)가 없음. PR 본문에 plan 원문이 붙어 있지 않음
- [ ] 명세서의 그룹 고유 기능이 모두 반영됨
- [ ] `import-log.md`가 갱신됨
