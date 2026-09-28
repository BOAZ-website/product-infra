# Implementation Plan: BOAZ 운영 AWS 인프라 Terraform 마이그레이션

> **참고용 문서.** 작업 순서·완료 조건의 기준은 노션 WBS·명세서(저장소 사본: `docs/wbs/`)임. 이 문서의 저장소 이름(`BOAZ-website/infra`), 시즌 변수(`season_mode` 단일 변수), Terraform 버전(1.9) 등은 정정 전 값이며, 현재 기준은 `design.md`·`requirements.md`와 `docs/wbs/`를 따름

## Overview

신규 `BOAZ-website/infra` 저장소에 운영 AWS 인프라를 lift-and-codify 방식으로 Terraform 코드화한다. 기존 운영 리소스는 삭제 후 재생성하지 않고 AWS CLI로 실제 식별자와 현재 설정을 확정한 뒤 선언적 `import` 블록으로 편입한다. `season_mode`는 `off`와 `on`만 허용하며, 운영 리소스에 대한 apply는 조사·plan·위험 action 검사·승인 게이트를 모두 통과한 뒤에만 가능하도록 한다.

기존 application workflow(`backend/.github/workflows/cd.yml`, `frontend/.github/workflows/deploy-www.yml`, `frontend/.github/workflows/deploy-dev.yml`)와 애플리케이션 코드는 수정하지 않는다. 단, 요구사항에서 명시한 기존 `backend/infra/scripts/README.md`의 이관·deprecated 안내는 문서 변경 대상으로 포함한다.

## Tasks


- [ ] 1. AWS CLI 사전 조사, 미확인 값 관리, 운영 apply 승인 경계 구축
  - [ ] 1.1 AWS CLI 조사 인벤토리와 미확인 상태 기록 구조 작성
    - 대상 영역: `BOAZ-website/infra/docs/inventory.md`, 조사 명령 템플릿
    - `aws ... --profile tf --region ap-northeast-2`를 기본으로 사용하고 CloudFront/ACM의 요구 리전을 분리한다.
    - VPC·서브넷·라우팅·IGW/NACL, EC2-A/B, SG 전체 규칙·CloudFront managed prefix list, RDS, S3, CloudFront, Route53, ACM, CodeDeploy, OIDC/role, `/boaz/infra/*` 12개, Target Group/ALB를 조사 대상으로 명시한다.
    - 시크릿 파라미터 값과 RDS password는 조회·출력하지 않고, 식별자·현재 설정을 확인하지 못한 항목은 `unconfirmed`로 남긴다.
    - 선행 작업: 없음. 이 작업이 끝나기 전에는 운영 리소스 import/apply 작업을 시작하지 않는다.
    - _관련 Requirement: 2.1, 2.7, 3.1, 3.9, 4.1, 4.2, 5.1, 6.1, 7.1, 7.4, 8.1, 8.2, 9.1, 12.4, 12.8, 13.4_
    - _관련 Property: P2, P7, P8, P9_

  - [ ] 1.2 미확인 값·결정 필요 항목과 운영 apply 승인 게이트 정의
    - 대상 영역: `BOAZ-website/infra/docs/decisions.md`, `docs/inventory.md`의 상태 규칙
    - state bucket/key, account/role ARN, EIP, EC2-B 상태 제어 방식, SecureString 전환, branch/Environment reviewer, S3 lifecycle, health preflight 증적 방식을 승인 대기 상태로 기록한다.
    - AWS 식별자·현재 설정·승인자가 확정되지 않은 동안 해당 리소스의 import/apply 및 apply workflow 활성화를 차단하는 규칙을 작성한다.
    - `tf` profile/account/region 확인 실패 시 변경 없이 중지하는 기준을 포함한다.
    - 선행 작업: 1.1
    - _관련 Requirement: 2.4, 2.7, 3.3, 3.9, 5.6, 5.7, 9.4, 12.2, 12.8, 13.12_
    - _관련 Property: P1, P2, P9_

  - [ ] 1.3 Import_Log 레코드 형식과 조사·승인 증적 저장 규칙 작성
    - 대상 영역: `BOAZ-website/infra/docs/import-log.md`
    - 그룹, Terraform 주소, AWS identifier, AWS CLI 출처·시점, 현재 설정, ownership, import commit, plan 결과, residual diff, destroy/replace 검사, 승인·복구 조치를 기록하는 템플릿을 만든다.
    - password·복호화된 SSM secret·secret fixture 원문은 어떤 필드에도 기록하지 않는다.
    - 표준 import 순서를 변경하는 경우에만 dependency 근거를 남기는 규칙과, 미확정 대상의 `unconfirmed`/`excluded` 처리 규칙을 포함한다.
    - 선행 작업: 1.1
    - _관련 Requirement: 3.4, 3.5, 3.6, 3.9, 4.5, 4.6, 13.4, 13.6_
    - _관련 Property: P2, P6_

- [ ] 2. 신규 `BOAZ-website/infra` 저장소 skeleton과 공통 실행 기반 구성
  - [ ] 2.1 Terraform 저장소 디렉터리 skeleton 생성
    - 대상 영역: `bootstrap/`, `envs/prod/`, `modules/`, `.github/workflows/`, `docs/`, `scripts/`, `tests/`, `.gitignore`
    - `bootstrap`, `envs/prod`, 8개 module 디렉터리, 문서·검증·CI 디렉터리를 생성하고 environment별 `envs/<env>/` 확장이 가능한 구조를 유지한다.
    - account ID·region·resource ID를 module 기본값이나 코드 literal로 넣지 않는다.
    - 선행 작업: 1.1
    - _관련 Requirement: 1.1~1.5, 1.6, 1.7, 13.1_
    - _관련 Property: P7_

  - [ ] 2.2 Terraform/AWS provider 버전, provider alias, lockfile 규칙 정의
    - 대상 영역: `bootstrap/versions.tf`, `envs/prod/versions.tf`, `bootstrap/providers.tf`, `envs/prod/providers.tf`, `.terraform.lock.hcl`
    - Terraform `>= 1.9.0, < 2.0.0`, AWS provider `>= 5.0.0, < 6.0.0`을 강제한다.
    - `ap-northeast-2` 기본 provider와 CloudFront ACM 조회용 `aws.us_east_1` alias를 구성하고 두 provider의 공통 `default_tags`를 정의한다.
    - `.terraform.lock.hcl` 생성·provider checksum 검증·버전 관리 정책을 마련한다.
    - 선행 작업: 2.1, 1.2에서 버전 관련 결정 확인
    - _관련 Requirement: 1.4, 1.6, 1.7, 7.9, 11.1_
    - _관련 Property: P9_

- [ ] 3. Bootstrap S3 state backend와 S3 native lock 구현
  - [ ] 3.1 bootstrap 전용 S3 state bucket과 보호 정책 구현
    - 대상 영역: `bootstrap/versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`
    - bootstrap state bucket의 versioning, SSE, public access block, 최소 권한 bucket policy와 lock object 권한을 구성한다.
    - state bucket·versioning·encryption·public access block·policy에 `prevent_destroy = true`를 적용하고 운영 리소스를 bootstrap에 포함하지 않는다.
    - DynamoDB table/resource와 `dynamodb_table` backend argument를 만들지 않는다.
    - 조사로 확정되지 않은 bucket 이름은 default/import ID로 사용하지 않으며, 기존 bucket 재사용은 account owner 승인과 Import_Log 증적이 있을 때만 허용한다.
    - 선행 작업: 1.1, 1.2, 2.2
    - _관련 Requirement: 2.1, 2.3, 2.4, 2.7_
    - _관련 Property: P1, P2, P6_

  - [ ] 3.2 envs/prod S3 backend와 bootstrap 후 초기화 절차 구현
    - 대상 영역: `envs/prod/backend.tf`, `backend.hcl.example`, `README.md`
    - `use_lockfile = true`만 사용하고 `envs/prod/terraform.tfstate`와 다른 환경 key가 겹치지 않게 한다.
    - bucket/key/region은 조사·승인 후 partial backend config로 주입하며, bootstrap 완료 전 `envs/prod` backend 초기화를 금지한다.
    - lock 획득 실패·backend init 실패 시 state와 AWS 리소스를 변경하지 않고 즉시 실패하도록 절차와 복구 문구를 정의한다.
    - 선행 작업: 3.1, 1.2
    - _관련 Requirement: 2.2, 2.4, 2.5, 2.6, 2.7, 13.1_
    - _관련 Property: P6, P9_

- [ ] 4. 재사용 가능한 8개 Terraform module 구현
  - [ ] 4.1 `modules/network` 구현
    - 대상 영역: `modules/network/{main,variables,outputs}.tf`
    - VPC·subnet·route table·IGW/NACL의 managed/data/excluded 경계를 표현하고, SG 규칙을 `aws_vpc_security_group_ingress_rule`/`egress_rule` 개별 리소스로 정의한다.
    - CloudFront managed prefix list → ALB SG, ALB SG → EC2 SG TCP 8080 관계를 조사 확정 ID로만 연결하고 과도한 SSH 규칙은 별도 승인 없이는 변경하지 않는다.
    - 선행 작업: 2.1, 2.2, 1.1~1.3
    - _관련 Requirement: 4.1~4.6, 11.1~11.4_
    - _관련 Property: P1, P2_

  - [ ] 4.2 `modules/iam` 구현
    - 대상 영역: `modules/iam/{main,variables,outputs}.tf`
    - GitHub OIDC provider, backend/frontend deploy role, infra plan/apply role, EC2 instance profile을 조사 확정값으로 관리한다.
    - EC2 role에는 SSM `GetParameter`/`GetParameters` with decryption, 배포 bundle S3 read, CodeDeploy agent에 필요한 최소 권한만 부여한다.
    - plan role과 apply role을 분리하고 장기 access key·추정 ARN·미확정 trust subject를 사용하지 않는다.
    - 선행 작업: 2.1, 2.2, 1.1~1.2
    - _관련 Requirement: 5.5, 8.2, 12.3, 12.4, 12.8_
    - _관련 Property: P6, P9_

  - [ ] 4.3 `modules/params` 구현
    - 대상 영역: `modules/params/{main,variables,outputs}.tf`
    - `/boaz/infra/*` 정확히 12개만 resource/module output에서 파생해 관리하고 literal identifier를 거부한다.
    - 앱 secret parameter는 값 관리 resource로 만들지 않고 존재·type·KMS key만 값 비노출 방식으로 검증한다. `with_decryption`과 실제 value output을 금지한다.
    - 기존 루트 parameter 이름을 변경하지 않고 `/boaz/app/*` 이관은 후속 결정으로 기록한다.
    - 선행 작업: 2.1, 2.2, 1.1~1.3
    - _관련 Requirement: 9.1~9.7_
    - _관련 Property: P6, P7_

  - [ ] 4.4 `modules/storage` 구현
    - 대상 영역: `modules/storage/{main,variables,outputs}.tf`
    - 배포 bundle·frontend·지원서 upload·archive bucket을 import 가능한 `aws_s3_bucket`과 별도 versioning, SSE, public access block, lifecycle, bucket policy resource로 정의한다.
    - 기존 bucket 이름과 workflow 계약을 보존하고, lifecycle 삭제 규칙은 보존 기간·승인자 결정 전에는 적용하지 않는다. 모든 운영 bucket에 `prevent_destroy = true`를 적용한다.
    - 선행 작업: 2.1, 2.2, 1.1~1.3
    - _관련 Requirement: 3.7, 7.1~7.3, 8.3~8.5, 11.3_
    - _관련 Property: P1, P2, P8_

  - [ ] 4.5 `modules/compute` 구현
    - 대상 영역: `modules/compute/{main,variables,outputs}.tf`
    - EC2-A/B의 확정 ID, profile, SG, subnet, origin attribute를 관리하고 EC2-B 상태는 `aws_ec2_instance_state`로 `season_mode`와 연결한다.
    - `drift_risk_confirmed = true`일 때 조사로 확인된 AMI·`user_data`·AWS-managed tag만 `lifecycle.ignore_changes`에 넣고 `app=boaz-api` 기능 태그는 ignore하지 않는다.
    - EC2-A/B에 `prevent_destroy = true`를 적용하고 EIP는 승인 전 생성하지 않는다. ASG 전환은 구현하지 않고 선택 근거를 문서화할 입력/출력을 제공한다.
    - 선행 작업: 2.1, 2.2, 4.2, 1.1~1.3
    - _관련 Requirement: 3.7, 5.1~5.8, 10.2~10.4, 11.2~11.4_
    - _관련 Property: P1, P3_

  - [ ] 4.6 `modules/database` 구현
    - 대상 영역: `modules/database/{main,variables,outputs}.tf`
    - RDS instance·subnet group·parameter group을 import 가능한 resource로 정의하고 SG module과 연결한다.
    - `multi_az`를 `season_mode`에 매핑하되 in-place 변경을 검증할 수 있게 하고, `deletion_protection = true`, `skip_final_snapshot = false`, `lifecycle.ignore_changes = [password]`를 강제한다.
    - password를 코드·tfvars·plan·output·log에 두지 않고 password diff·replace·destroy 시 apply를 차단한다.
    - 선행 작업: 2.1, 2.2, 4.1, 1.1~1.3
    - _관련 Requirement: 3.7, 6.1~6.7, 10.2~10.3_
    - _관련 Property: P1, P3, P6_

  - [ ] 4.7 `modules/cdn` 구현
    - 대상 영역: `modules/cdn/{main,variables,outputs}.tf`
    - API/www/dev CloudFront, Route53 zone/record, ACM certificate를 확정 ID/ARN/region으로 import·관리할 수 있게 한다.
    - API origin 수가 정확히 1개가 아니거나 현재 설정·ACM region/ARN이 미확정이면 plan/apply를 실패시키는 validation/precondition을 추가한다.
    - `season_mode=off`는 EC2-A resource attribute:8080, `on`은 ALB resource attribute DNS:80을 사용하고, SPA 403/404 → `/index.html`, cache policy, aliases, viewer certificate를 보존한다. CloudFront·Route53에 `prevent_destroy = true`를 적용한다.
    - 선행 작업: 2.1, 2.2, 4.5, 1.1~1.3
    - _관련 Requirement: 3.7, 7.4~7.10, 10.2~10.3, 10.9_
    - _관련 Property: P1, P3, P5_

  - [ ] 4.8 `modules/deploy` 구현 및 CodeDeploy 설정 분리
    - 대상 영역: `modules/deploy/{main,variables,outputs}.tf`, `docs/decisions.md`
    - CodeDeploy app/group, service role, target tag, bundle bucket, deployment configuration을 조사 결과 그대로 import·관리한다.
    - Terraform이 deployment group의 운영 계약을 `CodeDeployDefault.AllAtOnce`로 보존하도록 하고, `season-up.sh` 재배포 절차에서만 사용하는 `CodeDeployDefault.OneAtATime`을 Terraform 설정과 분리해 문서화한다.
    - 기존 backend workflow가 참조하는 app/group/bucket/ARN을 변경하지 않고 output으로 노출한다.
    - 선행 작업: 2.1, 2.2, 4.2, 4.4, 1.1~1.3
    - _관련 Requirement: 8.1~8.7, 11.3~11.4_
    - _관련 Property: P8, P9_

- [ ] 5. `envs/prod` wiring과 공통 안전 검증 구현
  - [ ] 5.1 `season_mode` 입력·canonical locals·공통 변수 모델 구현
    - 대상 영역: `envs/prod/variables.tf`, `locals.tf`, `terraform.tfvars.example`
    - `season_mode`는 정확히 `off`/`on`만 허용하고 invalid 입력은 variable validation에서 plan 전 실패시킨다.
    - `drift_risk_confirmed`, 조사 확정값, 승인된 정책을 입력으로 받되 secret value·추정 ID/ARN을 default로 제공하지 않는다.
    - off/on의 ALB/listener, EC2-B 상태·기능 태그, target 집합, API origin, RDS Multi-AZ canonical model을 locals로 표현한다.
    - 선행 작업: 4.1~4.8
    - _관련 Requirement: 5.2~5.4, 6.2~6.4, 10.1~10.4, 10.9, 12.6_
    - _관련 Property: P3_

  - [ ] 5.2 모든 module wiring·dependency·workflow 계약 output 연결
    - 대상 영역: `envs/prod/main.tf`, `outputs.tf`
    - network → iam/params/storage/compute/database → ALB/target → cdn/deploy 순으로 module을 연결하고 resource attribute 기반 참조를 사용한다.
    - ALB DNS와 EC2-A origin을 수동 입력값이 아닌 module/resource output으로 연결한다.
    - backend/frontend workflow 계약에 필요한 CodeDeploy app/group, bucket, distribution ID, role ARN을 민감하지 않은 output으로 노출한다.
    - 선행 작업: 5.1, 4.1~4.8
    - _관련 Requirement: 1.2~1.4, 5.9, 7.6~7.7, 8.3~8.5, 9.5_
    - _관련 Property: P3, P7, P8_

  - [ ] 5.3 destroy/replace·secret·identifier·parameter·origin 안전 gate 구현
    - 대상 영역: `envs/prod/checks.tf`, `scripts/verify-plan.py` 또는 동등한 검증 영역
    - plan JSON에서 protected resource(RDS, EC2, CloudFront, Route53 record, S3)의 `delete`/replacement action, RDS password diff, secret 실제 값 노출, 미확정 import ID, API origin 수/포트 위반, Infra Parameter count/reference 위반을 차단한다.
    - 과도한 SG 규칙은 해당 규칙 변경만 차단하고 무관한 resource apply는 허용하는 예외를 구현한다.
    - gate 실패 시 apply를 실행하지 않고 redacted plan·원인·복구 절차를 증적으로 남긴다.
    - 선행 작업: 5.2, 1.2~1.3
    - _관련 Requirement: 1.5, 2.6, 3.3, 3.7, 4.5, 6.4, 7.5, 9.1, 9.7, 12.7_
    - _관련 Property: P1, P2, P6, P7_

- [ ] 6. 단계별 선언적 import와 No changes/destroy-replace 게이트 연결
  - [ ] 6.1 network 그룹 선언적 import와 수렴 plan 구현
    - 대상 영역: `envs/prod/imports.tf`, `docs/import-log.md`
    - VPC → subnet → route table/IGW/NACL → SG/rules 순서로 조사 확정 ID만 Terraform 1.5+ `import` block에 추가한다.
    - import ID가 inventory와 문자 단위로 다르거나 설정을 확정하지 못하면 block/apply를 만들지 않고 `unconfirmed`/`excluded`로 기록한다.
    - 선행 작업: 4.1, 5.3, 1.1~1.3
    - _관련 Requirement: 3.1~3.6, 4.1~4.6_
    - _관련 Property: P1, P2_

  - [ ] 6.2 IAM 및 SSM infra parameter 그룹 선언적 import 구현
    - 대상 영역: `envs/prod/imports.tf`, `docs/import-log.md`, `modules/iam`, `modules/params`
    - OIDC/roles/policies와 존재가 확인된 `/boaz/infra/*` 12개를 조사 근거와 함께 import한다.
    - 앱 secret 파라미터는 값을 읽거나 import하지 않고 존재/type/KMS key만 비노출 검증 대상으로 남긴다.
    - 선행 작업: 6.1, 4.2~4.3, 5.3
    - _관련 Requirement: 3.1~3.6, 8.2, 9.1~9.7, 12.3~12.8_
    - _관련 Property: P6, P7, P9_

  - [ ] 6.3 S3 storage 그룹 선언적 import와 보호 설정 수렴
    - 대상 영역: `envs/prod/imports.tf`, `modules/storage`, `docs/import-log.md`
    - 배포 bundle·frontend·upload·archive bucket을 조사 확정 이름으로 import하고 versioning/SSE/public access block/lifecycle/policy의 residual diff를 기록한다.
    - bucket replacement/deletion이 계획되면 apply를 차단하며 lifecycle은 승인 전 변경하지 않는다.
    - 선행 작업: 6.2, 4.4, 5.3
    - _관련 Requirement: 3.1~3.8, 7.1~7.3, 8.3~8.5_
    - _관련 Property: P1, P2, P8_

  - [ ] 6.4 EC2-A/B compute 그룹 선언적 import와 drift 보호 수렴
    - 대상 영역: `envs/prod/imports.tf`, `modules/compute`, `docs/import-log.md`
    - EC2-A/B의 실제 instance ID, profile, SG, subnet, AMI/user_data drift 위험을 조사 결과와 대조해 import한다.
    - EC2-B의 상태·기능 태그와 `aws_ec2_instance_state`를 season controller에 연결하고, 기능 태그 변경이 ignore되지 않도록 plan을 검사한다.
    - 선행 작업: 6.3, 4.5, 5.1, 5.3
    - _관련 Requirement: 3.1~3.8, 5.1~5.8, 11.2~11.4_
    - _관련 Property: P1, P3_

  - [ ] 6.5 RDS database 그룹 선언적 import와 데이터 보호 gate 구현
    - 대상 영역: `envs/prod/imports.tf`, `modules/database`, `docs/import-log.md`
    - RDS instance·DB subnet group·parameter group·SG를 조사 확정 ID로 import한다.
    - `multi_az` on/off plan이 in-place인지 확인하고 password diff·RDS replacement/deletion·보호 설정 위반을 apply blocker로 기록한다.
    - 선행 작업: 6.4, 4.6, 5.3
    - _관련 Requirement: 3.1~3.8, 6.1~6.7_
    - _관련 Property: P1, P3, P6_

  - [ ] 6.6 Target Group·ALB/listener 그룹 import와 on dependency 연결
    - 대상 영역: `envs/prod/imports.tf`, `modules/network` 또는 `modules/cdn`, `docs/import-log.md`
    - 조사 확정 Target Group/ALB/listener의 등록 target·health check·port·SG·subnet을 import하고, off에서는 absent/on에서는 HTTP :80 present가 되도록 연결한다.
    - 모든 필수 target healthy 확인 전 CloudFront origin 변경이 실행되지 않도록 health gate 입력과 dependency를 연결한다.
    - 선행 작업: 6.5, 4.1, 4.5, 4.7, 5.3
    - _관련 Requirement: 3.1~3.8, 10.2~10.5, 10.8_
    - _관련 Property: P3, P4_

  - [ ] 6.7 CloudFront·Route53·ACM 그룹 import와 origin 보호 구현
    - 대상 영역: `envs/prod/imports.tf`, `modules/cdn`, `docs/import-log.md`
    - API/www/dev distribution, Route53 record/zone, ACM certificate를 AWS CLI로 확정한 ID/ARN/region으로 import한다.
    - API origin이 정확히 하나이고, on은 ALB DNS:80, off는 EC2-A:8080인지 검사한다. 인증서 리전·ARN 미확정 또는 origin 변경 replacement이면 apply를 차단한다.
    - 선행 작업: 6.6, 4.7, 5.3
    - _관련 Requirement: 3.1~3.8, 7.4~7.10, 10.5~10.9_
    - _관련 Property: P1, P3, P4, P5_

  - [ ] 6.8 CodeDeploy/deploy 계약 그룹 import와 설정 보존 구현
    - 대상 영역: `envs/prod/imports.tf`, `modules/deploy`, `docs/import-log.md`
    - CodeDeploy application/deployment group, service role, target tag, deployment config을 import하고 Terraform의 기존 운영 계약은 `AllAtOnce`로 보존한다.
    - 시즌 중 선택적 재배포에서만 `OneAtATime`을 사용하는 절차를 runbook 입력으로 분리하고 workflow 파일은 변경하지 않는다.
    - 선행 작업: 6.7, 4.8, 5.3
    - _관련 Requirement: 3.1~3.8, 8.1~8.7_
    - _관련 Property: P2, P8_

  - [ ] 6.9 단계별 No changes·destroy/replace·승인 gate와 최종 수렴 절차 구현
    - 대상 영역: `scripts/verify-plan.py`, `envs/prod/checks.tf`, `docs/import-log.md`, 각 단계 plan artifact
    - 각 import 단계에서 `terraform plan -out=plan.bin`/`terraform show -json`를 검사하고, 정확한 `No changes. Your infrastructure matches the configuration.` 또는 승인된 신규 관리 리소스만 통과시킨다.
    - destroy/replace, 미확정 ID, secret/password 노출, 허용되지 않은 residual diff가 있으면 apply를 차단한다.
    - 실제 AWS 식별자 확정·조사 근거·plan 수렴·운영 상태 비교·승인자가 모두 기록되기 전에는 다음 단계 apply로 진행하지 않는다.
    - 선행 작업: 6.1~6.8, 5.3
    - _관련 Requirement: 2.6, 3.2~3.5, 3.8, 3.9, 6.6, 7.10, 12.7, 13.6_
    - _관련 Property: P1, P2, P6_

- [ ] 7. 시즌 전환 안전 게이트와 기존 배포 계약/CI 구현
  - [ ] 7.1 시즌 시작 `on` dependency graph와 900초 health gate 구현
    - 대상 영역: `envs/prod/checks.tf`, `scripts/season-health-gate.sh` 또는 동등한 read-only preflight 영역
    - ALB 생성/ACTIVE → listener :80 → EC2-A/B target 등록 → 모든 target healthy → CloudFront origin ALB DNS:80 순서를 dependency와 증적으로 표현한다.
    - target unhealthy 또는 900초 timeout이면 origin 변경·후속 의존 작업을 차단하고 이전 검증 상태와 JSON 증적을 보존한다.
    - ALB DNS는 수동 입력이 아닌 `aws_lb` resource attribute로 사용한다.
    - 선행 작업: 6.6~6.7, 6.9, 5.1~5.3
    - _관련 Requirement: 5.3, 5.8, 10.3, 10.5, 10.8, 10.9, 13.3, 13.7_
    - _관련 Property: P3, P4, P10_

  - [ ] 7.2 모든 `off` 전환의 2단계 apply gate 구현
    - 대상 영역: `scripts/season-off-gate.sh`, `envs/prod/checks.tf`, `docs/runbook-season.md`의 실행 hook 영역
    - 1단계는 CloudFront origin을 EC2-A:8080으로 복귀시키고, 2단계는 CloudFront `Deployed`·origin·API health HTTP 200·5xx=0 확인 후에만 ALB/listener 제거를 허용한다.
    - `Deployed` 확인 실패·900초 timeout 시 ALB·기존 검증 상태를 보존하고 2단계 apply를 차단한다.
    - 최종 off plan은 EC2-B stopped/기능 태그 없음, EC2-A 단독 target, RDS Multi-AZ false를 포함해야 한다.
    - 선행 작업: 7.1, 6.7, 6.9
    - _관련 Requirement: 5.4, 5.8, 6.3, 7.7, 10.2, 10.6~10.8, 13.8, 13.12_
    - _관련 Property: P3, P5, P10_

  - [ ] 7.3 workflow output 계약 검사 구현
    - 대상 영역: `scripts/check-workflow-contract.py`, `envs/prod/outputs.tf`, `docs/workflow-contract.md`
    - backend app/group/bundle bucket/deploy role 및 frontend bucket/distribution ID/role ARN output과 기존 workflow 참조 토큰의 exact equality를 검사한다.
    - mismatch 또는 기존 workflow 수정 필요성이 감지되면 apply를 차단한다. 기존 workflow 파일은 읽기 전용 비교 대상으로만 사용한다.
    - 선행 작업: 5.2, 6.8, 6.9
    - _관련 Requirement: 8.3~8.7, 11.3~11.4_
    - _관련 Property: P8_

  - [ ] 7.4 PR용 Infrastructure CI 구현
    - 대상 영역: `.github/workflows/terraform-pr.yml`, `scripts/verify-plan.py`
    - PR에서 `terraform fmt -check`, `validate`, plan, destroy/replace/secret/contract gate를 실행하고 결과·redacted plan summary를 PR comment로 게시한다.
    - 세 핵심 검사가 모두 성공할 때만 apply 후보로 표시하고 하나라도 실패하면 apply 후보 표시를 금지한다.
    - OIDC를 사용하며 `id-token: write`를 명시하고 장기 access key를 저장·참조하지 않는다.
    - 선행 작업: 6.9, 7.3
    - _관련 Requirement: 12.1, 12.3, 12.6, 12.7_
    - _관련 Property: P1, P6, P8, P9_

  - [ ] 7.5 main apply와 protected Environment 승인 gate 구현
    - 대상 영역: `.github/workflows/terraform-apply.yml`, `docs/workflow-contract.md`
    - `main` merge 후 GitHub Environment 수동 승인 성공 전에는 apply를 실행하지 않도록 구성한다.
    - plan 전용 read role과 apply 전용 write role, OIDC trust 조건·ARN·권한 범위를 분리해 문서화하고 미확정 시 workflow를 비활성 상태로 둔다.
    - apply 전 동일한 destroy/replace/secret/contract gate와 backend/lock 성공 여부를 재검사한다.
    - 선행 작업: 7.4, 1.2, 4.2, 6.9
    - _관련 Requirement: 2.2, 2.6, 8.2, 12.2~12.4, 12.7~12.8_
    - _관련 Property: P1, P6, P9_

  - [ ] 7.6 예약 drift 감지 CI 구현
    - 대상 영역: `.github/workflows/terraform-drift.yml`, `scripts/verify-plan.py`
    - 직전 성공 실행 후 24시간 이내에 최소 한 번 read-only plan을 실행하고 변경 또는 실패 시 담당자 알림과 redacted 증적을 남긴다.
    - drift workflow는 자동 apply하지 않으며 secret·password·state 내용을 노출하지 않는다.
    - 선행 작업: 7.4, 7.5, 5.3
    - _관련 Requirement: 12.5~12.7_
    - _관련 Property: P6, P9_

- [ ] 8. Hypothesis 기반 PBT와 정적·통합 검증 구현
  - [ ] 8.1 Property 1 protected resource action gate PBT 작성
    - 대상 영역: `tests/property/test_design_invariants.py`
    - protected resource 주소와 `no-op`/`update`/`create`/`delete`/replacement action 조합을 생성해 delete·replace가 하나라도 있으면 false가 되는지 `@settings(max_examples=100)` 이상으로 검증한다.
    - **Property 1: 보호 리소스 무교체 및 action gate**
    - **Validates: Requirements 3.3, 3.7, 6.7, 7.10, 12.7**
    - 선행 작업: 5.3, 6.9

  - [ ] 8.2 Property 3 `season_mode` canonical model PBT 작성
    - 대상 영역: `tests/property/test_design_invariants.py`
    - `off`, `on`, 임의 invalid 문자열을 생성해 canonical 상태 매핑과 비교하고 invalid 입력은 validation error인지 검증한다.
    - **Property 3: season_mode 상태 매핑**
    - **Validates: Requirements 5.3~5.4, 6.2~6.3, 10.1~10.3**
    - 선행 작업: 5.1, 6.4~6.7

  - [ ] 8.3 Property 6 secret redaction PBT 작성
    - 대상 영역: `tests/property/test_design_invariants.py`
    - 임의 secret 문자열과 중첩 plan/state/log fixture를 생성해 redaction 결과에 원문 substring이 남지 않고 config/output/state가 실제 Secret_Parameter 값을 포함하지 않는지 검증한다.
    - **Property 6: 시크릿 redaction 및 비노출**
    - **Validates: Requirements 2.6, 6.4, 9.2~9.3, 9.7, 12.6~12.7**
    - 선행 작업: 8.1, 5.3

  - [ ] 8.4 Property 7 Infra Parameter 정확히 12개·파생 관계 PBT 작성
    - 대상 영역: `tests/property/test_design_invariants.py`
    - 누락·중복·추가 항목과 resource/module reference·hardcoded literal을 생성해 정확히 12개이고 모든 값이 reference일 때만 통과하는지 검증한다.
    - **Property 7: `/boaz/infra/*` 12개 파라미터 파생**
    - **Validates: Requirements 9.1, 9.5~9.7**
    - 선행 작업: 8.2, 4.3, 5.3

  - [ ] 8.5 Property 8 workflow output contract equality PBT 작성
    - 대상 영역: `tests/property/test_design_invariants.py`
    - app/group, bucket, distribution ID, role ARN map을 생성해 완전 일치만 통과하고 단일 값 변경은 실패하는지 검증한다.
    - **Property 8: 기존 workflow output 계약 보존**
    - **Validates: Requirements 8.3~8.6, 11.3**
    - 선행 작업: 8.4, 7.3

  - [ ] 8.6 Property 2 import 수렴·No changes 정적 검사 작성
    - 대상 영역: `tests/integration/test_import_convergence.py`, `scripts/verify-plan.py`
    - inventory의 확정 주소/ID와 import block을 대조하고 plan JSON의 빈 `resource_changes` 또는 승인된 신규 관리 resource만 통과시키며 미확정 ID·residual diff를 실패시킨다.
    - **Property 2: 선언적 import 수렴**
    - **Validates: Requirements 3.1~3.6, 3.9, 13.6**
    - 선행 작업: 6.1~6.9

  - [ ] 8.7 Property 4 시즌 시작 dependency·health gate 통합/fixture 테스트 작성
    - 대상 영역: `tests/integration/test_season_on_gate.py`, `scripts/season-health-gate.sh`
    - ALB → listener → target 등록 → all healthy → origin 순서를 통과 fixture와 unhealthy/900초 timeout 실패 fixture로 검증한다.
    - **Property 4: 시즌 시작 dependency와 health gate**
    - **Validates: Requirements 10.5, 10.8, 13.7**
    - 선행 작업: 7.1

  - [ ] 8.8 Property 5 시즌 종료 2단계 안전 순서 통합/fixture 테스트 작성
    - 대상 영역: `tests/integration/test_season_off_gate.py`, `scripts/season-off-gate.sh`
    - origin 복귀와 fresh `Deployed` evidence 없이 ALB 제거가 허용되지 않으며 gate 실패 시 이전 검증 상태를 유지하는지 검증한다.
    - **Property 5: 시즌 종료 2단계 안전 순서**
    - **Validates: Requirements 10.6~10.8, 13.8**
    - 선행 작업: 7.2, 8.7

  - [ ] 8.9 Property 9 OIDC·CI 안전 정적 검사 작성
    - 대상 영역: `tests/static/test_ci_security.py`, `.github/workflows/*.yml`
    - 장기 access key reference 0, AWS job의 `id-token: write`, PR fmt/validate/plan/comment, protected apply gate, daily drift 조건을 YAML 정적으로 검증한다.
    - **Property 9: OIDC·CI 안전 게이트**
    - **Validates: Requirements 8.2, 12.1~12.5**
    - 선행 작업: 7.4~7.6

  - [ ] 8.10 Property 10 runbook acceptance evidence 통합 테스트 작성
    - 대상 영역: `tests/integration/test_runbook_acceptance.py`, `docs/runbook-season.md`의 evidence schema
    - ALB 상태, 모든 target healthy, CloudFront origin/Deployed, RDS Multi-AZ, API health HTTP 200, 5xx=0의 전환 전·중·후 evidence 누락/실패를 인수 실패로 판정한다.
    - **Property 10: 런북 인수 검증**
    - **Validates: Requirements 13.2~13.3, 13.7~13.12**
    - 선행 작업: 7.1~7.2, 9.2

  - [ ] 8.11 Terraform 정적·대표 통합 검증 실행 구성
    - 대상 영역: `tests/static/`, `tests/integration/`, CI test commands
    - `terraform fmt -check -recursive`, `init -backend=false`, `validate`, lock checksum, literal ID/region/account 검사, DynamoDB lock 부재, secret literal 부재, deprecated script 실행 참조 검사와 plan JSON 검사 명령을 구성한다.
    - AWS에 반복 요청하지 않는 fixture 테스트와 실제 AWS 대표 smoke/import/on/off 검증을 분리한다.
    - 선행 작업: 6.9, 7.4~7.6, 8.1~8.10
    - _관련 Requirement: 1.5~1.7, 2.1~2.7, 3.2~3.9, 12.1~12.8, 13.6~13.12_
    - _관련 Property: P1~P10_

- [ ] 9. 한국어 운영 문서와 구 스크립트 deprecated 처리
  - [ ] 9.1 한국어 README 작성
    - 대상 영역: `BOAZ-website/infra/README.md`
    - 저장소 구조, AWS profile `tf`, 확정 Terraform/provider 버전, bootstrap/init, 일상 plan/apply, 기대 성공 조건, 실패 시 중지 기준, state key/lock/승인 gate를 기록한다.
    - 운영 apply는 식별자 확정·plan gate·승인 전에는 실행하지 않는다는 원칙을 명시한다.
    - 선행 작업: 3.2, 6.9, 7.4~7.6
    - _관련 Requirement: 1.1~1.7, 2.1~2.7, 13.1, 13.6_
    - _관련 Property: P1, P2, P6, P9_

  - [ ] 9.2 한국어 시즌 전환 runbook 작성
    - 대상 영역: `BOAZ-website/infra/docs/runbook-season.md`
    - 사전 점검, `on` apply, ALB/listener/target health/CloudFront/RDS/API health 검증, 900초 timeout, 실패 복구를 기록한다.
    - 모든 `off` 전환에 CloudFront origin 복귀 apply → `Deployed` 확인 → ALB 제거 apply의 2단계 절차를 강제한다.
    - Terraform deployment group의 `AllAtOnce`와 `season-up.sh` 재배포 시 일시적인 `OneAtATime`을 구분해 기록하고, workflow/app 코드는 수정하지 않는다.
    - 선행 작업: 7.1~7.2, 4.8
    - _관련 Requirement: 8.7, 10.5~10.8, 10.10~10.11, 13.2~13.3, 13.7~13.12_
    - _관련 Property: P4, P5, P10_

  - [ ] 9.3 최종 Import_Log와 No changes/승인 증적 갱신
    - 대상 영역: `BOAZ-website/infra/docs/import-log.md`
    - 모든 import·data source·excluded·unconfirmed 대상, AWS CLI 근거·시점, plan artifact, residual diff, destroy/replace 검사, 승인·복구 조치를 실제 단계 결과로 갱신한다.
    - 최종 plan의 정확한 No changes 문구와 실행 시점·검증자를 기록하고 secret/password는 기록하지 않는다.
    - 선행 작업: 6.9, 8.6, 9.1
    - _관련 Requirement: 3.5~3.6, 13.4, 13.6_
    - _관련 Property: P1, P2, P6_

  - [ ] 9.4 workflow contract 및 CI 운영 계약 문서 작성
    - 대상 영역: `BOAZ-website/infra/docs/workflow-contract.md`
    - 기존 backend/frontend workflow가 참조하는 app/group/bucket/distribution/role 계약, Terraform output 비교 규칙, plan/apply role, OIDC, Environment 승인 규칙을 기록한다.
    - 기존 application workflow 파일을 복사·수정하지 않고 참조 토큰만 검증 대상으로 명시한다.
    - 선행 작업: 7.3~7.6
    - _관련 Requirement: 8.3~8.7, 12.1~12.8_
    - _관련 Property: P8, P9_

  - [ ] 9.5 결정 필요 항목과 승인 결과 문서화
    - 대상 영역: `BOAZ-website/infra/docs/decisions.md`
    - EIP, EC2-B `aws_ec2_instance_state`/ASG 비교, SecureString, branch 전략, Environment reviewer, S3 lifecycle, bootstrap bucket 재사용, health evidence 방식을 결정/미결정 상태로 기록한다.
    - 미결정 항목과 연관 resource의 운영 apply/workflow 활성화 차단 상태를 함께 기록한다.
    - 선행 작업: 1.2, 3.1, 4.5, 7.5
    - _관련 Requirement: 2.7, 5.6~5.7, 9.4, 12.8, 13.4_
    - _관련 Property: P9_

  - [ ] 9.6 기존 구 스크립트의 이관·deprecated 안내 추가
    - 대상 영역: `backend/infra/scripts/README.md` (문서만)
    - `season-up.sh`, `season-down.sh`, `cf_set_origin.py`, `register-ssm-params.sh`를 신규 `BOAZ-website/infra`와 Terraform/runbook으로 이관하는 안내, deprecated 상태, 삭제 전제(DoD 충족 및 별도 승인)를 기록한다.
    - 기존 스크립트 구현, application workflow, 애플리케이션 코드는 이 작업에서 수정하지 않는다.
    - 선행 작업: 9.1~9.2
    - _관련 Requirement: 9.5~9.6, 10.10, 13.5_
    - _관련 Property: P7_

- [ ] 10. 최종 자동 리허설과 Definition of Done 검증
  - [ ] 10.1 최종 plan·lock·보호 resource·secret·계약 자동 acceptance harness 구현
    - 대상 영역: `scripts/acceptance-check.py`, `tests/integration/test_definition_of_done.py`
    - 최종 `envs/prod` plan의 No changes, 미확인 항목 0 또는 승인된 exclusion, protected action gate, secret 비노출, output contract, CI gate 결과를 자동 판정한다.
    - 실패 시 운영 apply를 승인하지 않고 마지막 검증 상태·차단 사유·복구 조치를 증적으로 남긴다.
    - 선행 작업: 6.9, 7.3~7.6, 8.11, 9.1~9.5
    - _관련 Requirement: 3.2~3.3, 8.5~8.6, 9.7, 12.7~12.8, 13.6, 13.12_
    - _관련 Property: P1, P2, P6, P8, P9, P10_

  - [ ] 10.2 `season_mode=on` 대표 리허설 evidence 자동 수집
    - 대상 영역: `scripts/rehearsal-on.sh` 또는 동등한 자동 검증 영역, `docs/import-log.md` evidence
    - ALB ACTIVE, listener :80, EC2-A/B all healthy, CloudFront origin ALB DNS:80, RDS Multi-AZ true, API health HTTP 200, 전환 전·중·후 5xx=0을 확인하고 시점별 evidence를 저장한다.
    - unhealthy/timeout이면 origin 변경과 후속 apply를 중지한다.
    - 선행 작업: 7.1, 8.7, 8.10, 10.1
    - _관련 Requirement: 10.3, 10.5, 10.8, 13.3, 13.7, 13.11~13.12_
    - _관련 Property: P3, P4, P10_

  - [ ] 10.3 `season_mode=off` 2단계 대표 리허설 evidence 자동 수집
    - 대상 영역: `scripts/rehearsal-off.sh` 또는 동등한 자동 검증 영역, `docs/import-log.md` evidence
    - 1단계 origin EC2-A:8080 복귀와 CloudFront `Deployed`를 확인한 뒤에만 2단계 ALB 제거를 수행하고, EC2-B stopped/기능 태그 없음, EC2-A 단독 target, RDS Multi-AZ false, API health HTTP 200을 검증한다.
    - `Deployed`가 아니면 ALB를 제거하지 않고 마지막 검증 상태를 보존한다.
    - 선행 작업: 7.2, 8.8, 10.1~10.2
    - _관련 Requirement: 10.2, 10.6~10.8, 13.8, 13.11~13.12_
    - _관련 Property: P3, P5, P10_

  - [ ] 10.4 기존 backend/frontend 배포 계약 대표 검증 자동화
    - 대상 영역: `tests/integration/test_workflow_contract_acceptance.py`, `docs/import-log.md`
    - backend `workflow_dispatch`의 CodeDeploy app/group/S3 계약과 frontend dev/main의 S3 sync/CloudFront invalidation 계약을 output과 비교하는 검증을 구성한다.
    - 기존 workflow 파일이나 앱 코드를 수정하지 않고, 실제 대표 실행의 성공 결과를 기록할 수 있는 evidence schema만 제공한다.
    - 선행 작업: 7.3, 8.5, 9.4, 10.1
    - _관련 Requirement: 8.3~8.7, 13.9~13.10_
    - _관련 Property: P8, P9_

  - [ ] 10.5 최종 Definition of Done 승인 gate와 deprecated 상태 확인
    - 대상 영역: `scripts/acceptance-check.py`, `README.md`, `docs/import-log.md`, `docs/decisions.md`
    - 최종 No changes, 조사/관리 제외 완료, on→검증→off 리허설, API 200/5xx=0, backend/frontend 대표 배포 계약, CI fmt/validate/plan/승인 apply/drift, 한국어 문서 완료 여부를 하나의 checklist로 판정한다.
    - 모든 DoD가 충족되기 전 운영 apply 승인 및 구 스크립트 삭제를 차단하고, 충족 후에도 기존 스크립트는 별도 승인 전까지 deprecated 안내 상태로 유지한다.
    - 선행 작업: 10.1~10.4, 9.6
    - _관련 Requirement: 9.5~9.6, 10.10~10.11, 12.1~12.8, 13.1~13.12_
    - _관련 Property: P1~P10_

- [ ] 11. 체크포인트 - 각 단계의 자동 검증과 승인 증적이 통과할 때까지 다음 단계로 진행하지 않는다.
  - 조사 식별자 미확정, backend/lock 실패, destroy/replace, secret 노출, unhealthy target, CloudFront 미배포, workflow 계약 불일치 중 하나라도 있으면 운영 apply를 중지한다.

- [ ] 12. 최종 체크포인트 - 기존 application workflow와 앱 코드가 변경되지 않았고, 운영 apply 승인 전 모든 gate와 Definition of Done이 통과했는지 확인한다.
  - 확인이 끝나면 `tasks.md`의 작업을 실행할 수 있으며, 각 항목 옆의 **Start task**로 순차 또는 의존성 wave에 따라 실행한다.

## Notes

- 각 작업의 `대상 영역`은 `product-infra` 저장소 기준이며, `product-infra/.kiro/specs/product-infra-migration`은 계획 산출물 위치다.
- 작업 간 병렬성은 아래 dependency graph로 정의한다. 같은 파일을 수정하는 작업은 서로 다른 wave에 배치한다.
- AWS 식별자와 현재 설정이 확정되지 않은 상태에서 추정값으로 import/apply하지 않는다. 조사 실패·미확정·승인 대기 상태는 `inventory.md`, `decisions.md`, `import-log.md`에 남긴다.
- 운영 리소스에 대한 apply 전에는 단계별 plan이 통과하고, destroy/replace·secret/password 노출·workflow 계약 불일치가 없으며, 필요한 운영 승인이 완료되어야 한다.
- PBT와 정적·통합 검증 작업은 설계의 Correctness Properties가 있는 순수 판정 로직·fixture 및 외부 상태 검증에 적용하며, 구현 완료에 필요한 필수 작업으로 유지한다.
- PBT는 설계의 Correctness Properties가 있는 순수 판정 로직/fixture에만 적용하고, AWS 외부 상태는 정적 검사와 대표 통합/smoke 검증으로 확인한다.
- 이 계획은 구현·테스트·검증 산출물만 포함한다. 운영 승인 자체, 실제 production apply, 사용자 교육·마케팅은 coding agent가 자동으로 수행하지 않는다.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "2.2"] },
    { "id": 2, "tasks": ["3.1"] },
    { "id": 3, "tasks": ["3.2", "4.1", "4.2", "4.3"] },
    { "id": 4, "tasks": ["4.4", "4.5", "4.6", "4.7", "4.8"] },
    { "id": 5, "tasks": ["5.1"] },
    { "id": 6, "tasks": ["5.2", "5.3"] },
    { "id": 7, "tasks": ["6.1"] },
    { "id": 8, "tasks": ["6.2"] },
    { "id": 9, "tasks": ["6.3"] },
    { "id": 10, "tasks": ["6.4"] },
    { "id": 11, "tasks": ["6.5"] },
    { "id": 12, "tasks": ["6.6"] },
    { "id": 13, "tasks": ["6.7"] },
    { "id": 14, "tasks": ["6.8"] },
    { "id": 15, "tasks": ["6.9"] },
    { "id": 16, "tasks": ["7.1", "7.3"] },
    { "id": 17, "tasks": ["7.2", "7.4"] },
    { "id": 18, "tasks": ["7.5", "7.6"] },
    { "id": 19, "tasks": ["8.1"] },
    { "id": 20, "tasks": ["8.2"] },
    { "id": 21, "tasks": ["8.3"] },
    { "id": 22, "tasks": ["8.4"] },
    { "id": 23, "tasks": ["8.5"] },
    { "id": 24, "tasks": ["8.6", "8.9"] },
    { "id": 25, "tasks": ["8.7"] },
    { "id": 26, "tasks": ["8.8"] },
    { "id": 27, "tasks": ["8.10"] },
    { "id": 28, "tasks": ["8.11"] },
    { "id": 29, "tasks": ["9.1", "9.2", "9.4", "9.5", "9.6"] },
    { "id": 30, "tasks": ["9.3"] },
    { "id": 31, "tasks": ["10.1"] },
    { "id": 32, "tasks": ["10.2", "10.4"] },
    { "id": 33, "tasks": ["10.3"] },
    { "id": 34, "tasks": ["10.5"] }
  ]
}
```
