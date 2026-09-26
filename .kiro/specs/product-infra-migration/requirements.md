# Requirements Document

## Introduction

BOAZ 공식 홈페이지(`www.bigdataboaz.com`)와 API 서버의 운영 AWS 인프라를 신규 `BOAZ-website/product-infra` Terraform 저장소로 코드화하는 기능이다. 현재 운영은 `backend/infra/scripts/`의 AWS CLI·Python 스크립트와 콘솔 수작업에 의존하며, 시즌 전환·리소스 식별자·SSM 파라미터가 애플리케이션 저장소에 분산되어 있다.

이 기능은 현행 아키텍처를 유지하는 lift-and-codify 범위다. 운영 리소스를 삭제 후 재생성하지 않고 선언적 import로 state에 편입하며, `season_capacity`와 `api_origin` 두 변수로 시즌 전환 상태를 표현하고, PR 기반 plan/apply·state 보호·런북·검증 체계를 제공한다.

### 확인된 현재 상태

- 작업 공간은 `backend/`, `frontend/`, `frontend_admin/`이 분리된 독립 저장소 구조이며, 인프라 Terraform 저장소는 아직 존재하지 않는다.
- 운영 API 배포는 GitHub Actions OIDC → S3 `boaz-codedeploy-bucket` → CodeDeploy `boaz-backend`/`codedeploy-prod` → EC2 흐름을 사용한다.
- 프론트엔드 배포는 GitHub Actions OIDC → S3 sync → CloudFront invalidation 흐름을 사용한다. 운영·개발 배포가 참조하는 버킷·CloudFront 배포 ID·롤 ARN은 GitHub Secret에 있다.
- 현행 시즌 스크립트는 평시에 EC2-A 직결, 시즌 중 `boaz-alb`와 EC2-A/B, RDS Multi-AZ를 사용하며 CloudFront API 배포의 단일 origin을 교체한다.
- 지역은 기본적으로 `ap-northeast-2`이며 CloudFront용 ACM은 `us-east-1` provider가 필요할 수 있다.

### 범위 밖

- `admin.bigdataboaz.com` 신규 환경 구성
- 백엔드 dev 환경 신설
- ECS/EKS/ASG 또는 Blue-Green 등 아키텍처 전환
- 애플리케이션 코드, CodeDeploy hook, Spring 설정, 기존 애플리케이션 저장소 workflow 수정
- 이번 마이그레이션에서 앱 시크릿 파라미터 이름을 `/boaz/app/*`로 변경

## Glossary

- **Infra_Repository**: `BOAZ-website/product-infra` 신규 저장소.
- **Terraform_Configuration**: Terraform ≥ 1.9와 AWS Provider ≥ 5.x로 작성된 `bootstrap/`, `modules/`, `envs/prod/` 구성.
- **Import_Procedure**: 운영 리소스의 실제 식별자와 설정을 조사하고 Terraform `import` 블록으로 state에 편입한 뒤 plan을 수렴시키는 절차.
- **Protected_Resource**: EC2, RDS, CloudFront, Route53, S3 등 운영 중 삭제·교체 시 중단 또는 데이터 손실을 일으킬 수 있어 삭제와 교체를 차단해야 하는 리소스.
- **Season_Controller**: `season_capacity`·`api_origin` 변수와 조건식·리소스 의존성으로 평시와 모집 시즌 상태를 제어하는 Terraform 구성.
- **Season_Mode**: `season_capacity`(`off`/`on`: ALB·EC2-B·Target Group 등록·RDS Multi-AZ)와 `api_origin`(`ec2`/`alb`: API CloudFront origin)의 조합. 평시는 `off`+`ec2`, 모집 시즌은 `on`+`alb`이며, `off`+`alb` 조합은 허용하지 않는다.
- **State_Backend**: S3 state 버킷과 S3 native lock(`use_lockfile = true`)으로 Terraform state 동시성을 보호하는 구성.
- **Drift_Risk_Confirmed**: AWS CLI 사전 조사로 AMI·`user_data`·AWS 관리 태그 변경이 EC2 인스턴스 교체를 일으킬 위험이 확인되었음을 나타내는 boolean 판단값.
- **Bootstrap_Configuration**: State_Backend 자체를 최초 생성하는 별도 Terraform 구성.
- **Infra_Parameter**: `/boaz/infra/*` 아래의 인프라 식별자 파라미터. 리소스 attribute에서 값을 파생해 Terraform이 관리한다.
- **Secret_Parameter**: `DB_*`, `JWT_SECRET`, OAuth 클라이언트, `SWAGGER_*` 등 앱 시크릿 SSM 파라미터. 값은 Terraform이 읽거나 변경하지 않는다.
- **Infrastructure_CI**: Infra_Repository의 PR plan, main apply, drift 감지를 수행하는 GitHub Actions 파이프라인.
- **Import_Log**: 단계별 import 대상, 조사 근거, plan 결과, 잔여 diff, 관리 제외 사유를 기록하는 문서.
- **Season_Runbook**: 시즌 전환의 사전 점검·apply·검증·실패 복구 절차를 기술한 한국어 문서.
- **No_Changes_Plan**: import와 실제 속성 조정이 끝난 뒤 `terraform plan`이 `No changes. Your infrastructure matches the configuration.`을 출력하는 상태.

## Requirements

### Requirement 1: 인프라 저장소와 Terraform 구조

**User Story:** 운영자로서 애플리케이션 코드와 분리된 한 곳에서 인프라를 관리하고 싶다. 인프라 변경과 애플리케이션 배포의 수명주기가 다르기 때문이다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Infra_Repository SHALL 인프라 코드와 Terraform 구성의 기준 저장소를 `BOAZ-website/product-infra`로 두고, 저장소에 해당 구성이 존재함을 검증 가능하게 한다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL 재사용 가능한 모듈을 `modules/network`, `modules/compute`, `modules/database`, `modules/storage`, `modules/cdn`, `modules/deploy`, `modules/iam`, `modules/params` 경로로 분리한다.
3. **[Ubiquitous]** THE Terraform_Configuration SHALL 환경별 진입점을 `envs/prod/`에 두고, 동일 규칙의 `envs/<env>/` 추가로 환경 확장이 가능한 구조를 제공한다.
4. **[Ubiquitous]** THE Terraform_Configuration SHALL 계정 ID·리전·리소스 ID를 모듈 코드에 하드코딩하지 않고 변수·provider 설정·관리 리소스 attribute 참조로만 공급한다.
5. **[Unwanted-event]** IF 모듈 코드에 계정 ID·리전·리소스 ID의 리터럴이 존재하거나 필수 구조 검증에 실패하면, THEN THE Terraform_Configuration SHALL plan·apply를 허용하지 않고 실패 원인과 조치 결과를 CI 결과 또는 Import_Log에 기록한다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL `required_version`으로 Terraform 버전을 `>= 1.11.0, < 2.0.0`으로 제한하고 AWS Provider 버전을 `docs/records/decisions.md`의 "AWS provider 버전" 결정 범위(현재 기준 `>= 5.0.0, < 6.0.0`)로 제한한다.
7. **[Ubiquitous]** THE Infra_Repository SHALL `.terraform.lock.hcl`을 버전 관리 대상으로 커밋하고 provider 무결성 검증에 사용한다.

### Requirement 2: State 저장·동시성·부트스트랩 보호

**User Story:** 운영자로서 여러 담당자가 동시에 apply해도 state 손상이나 공개가 발생하지 않기를 원한다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE State_Backend SHALL AWS CLI 사전 조사로 식별자를 확정한 전용 S3 버킷에 state를 저장하고, 버저닝·서버 측 암호화·퍼블릭 액세스 차단의 활성 상태를 plan 또는 AWS 조회 결과로 검증한다.
2. **[Ubiquitous]** THE State_Backend SHALL S3 native lock인 `use_lockfile = true`를 확정된 유일한 락 방식으로 사용하고, 동시 lock 획득 실패를 즉시 apply 실패로 기록한다.
3. **[Ubiquitous]** THE State_Backend SHALL DynamoDB 락 대안을 활성화하지 않고 S3 native lock 방식만 운영 절차와 구성에 사용한다.
4. **[Ubiquitous]** THE Bootstrap_Configuration SHALL state 버킷과 lock 리소스를 환경 구성과 분리하고 해당 리소스에 `prevent_destroy = true`를 적용하며, bootstrap 완료 전에는 환경 구성이 backend를 사용해 초기화되지 않도록 한다.
5. **[Ubiquitous]** THE State_Backend SHALL 환경별 state key를 서로 겹치지 않게 분리하고 운영 key는 사전 조사와 결정으로 확정한 값을 README와 backend 설정에 동일하게 기록한다.
6. **[Unwanted-event]** IF Terraform plan·state·로그에 Secret_Parameter의 실제 값이 포함되거나 backend 초기화·lock 획득에 실패하면, THEN THE Terraform_Configuration SHALL plan·apply를 차단하고 기존 state를 변경하지 않은 채 실패 원인과 복구 절차를 기록한다.
7. **[Unwanted-event]** IF State_Backend 또는 bootstrap 리소스의 실제 식별자가 AWS CLI 사전 조사로 확정되지 않으면, THEN THE Bootstrap_Configuration SHALL 추정값으로 생성·import하지 않고 조사가 완료될 때까지 운영 apply를 차단한다.

### Requirement 3: 운영 리소스의 무중단 선언적 import

**User Story:** 운영자로서 이미 서비스 중인 리소스를 코드화하되 다운타임과 재생성을 발생시키고 싶지 않다.

#### Acceptance Criteria

1. **[Event-driven]** WHEN AWS CLI 사전 조사로 실제 식별자가 확정되고 Import_Log에 조사 근거가 기록되면, THE Import_Procedure SHALL Terraform 1.5 이상 선언적 `import` 블록으로 해당 리소스를 취득한다.
2. **[Event-driven]** WHEN import와 속성 정합화가 완료되면, THE Import_Procedure SHALL 같은 커밋의 `envs/prod` plan에서 `No_Changes_Plan`을 달성하거나 허용된 신규 관리 리소스 목록과 사유를 Import_Log에 기록한다.
3. **[Unwanted-event]** IF plan에 `destroy` 또는 `replace`가 하나라도 포함되거나 import 대상 ID가 조사 근거와 일치하지 않으면, THEN THE Import_Procedure SHALL apply를 차단하고 실제 상태와 일치하도록 정의·식별자를 수정한 뒤 재검토한다.
4. **[Ubiquitous]** THE Import_Procedure SHALL 네트워크(VPC·서브넷·SG) → IAM·SSM → S3 → EC2 → RDS → Target Group·ALB → CloudFront·Route53·ACM → CodeDeploy 순의 표준 순서로 그룹을 나누며, 명시적 순서 변경이 선언되지 않은 경우 이 표준 순서를 따른 것으로 간주한다. 명시적으로 순서를 변경한 경우에만 의존성 근거를 Import_Log에 기록한다.
5. **[Event-driven]** WHEN 각 리소스 그룹의 import를 완료하면, THE Import_Procedure SHALL Import_Log에 리소스 주소, AWS CLI로 확정한 실제 식별자, 조사 출처·시점, plan 결과, 잔여 diff, 관리 제외 사유를 기록한다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL 관리하지 않을 리소스를 데이터 소스 또는 관리 제외 목록으로 명시하고 각 제외 사유와 영향 범위를 기록한다.
7. **[Ubiquitous]** THE Terraform_Configuration SHALL Protected_Resource에 `prevent_destroy = true`를 적용하며 대상에는 RDS·EC2·CloudFront·Route53 레코드·S3가 포함된다.
8. **[Ubiquitous]** THE Import_Procedure SHALL 운영 트래픽을 중단시키는 삭제 후 재생성 방식으로 import를 수행하지 않고 import 전·후 운영 상태 비교 결과를 Import_Log에 기록한다.
9. **[Unwanted-event]** IF import 대상의 식별자·현재 설정·관리 여부를 AWS CLI 사전 조사로 확정할 수 없으면, THEN THE Import_Procedure SHALL 해당 대상을 import·apply하지 않고 관리 제외 또는 추가 조사 상태로 Import_Log에 남긴다.

### Requirement 4: 네트워크와 보안 그룹

**User Story:** 운영자로서 현재 트래픽 경로와 최소 권한 네트워크 규칙을 drift 없이 관리하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 VPC·서브넷·라우팅 테이블·인터넷 게이트웨이를 import하거나, 각 미관리 대상의 제외 사유와 현재 연결 관계를 기록한다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL 사전 조사로 확정한 ALB Security Group의 inbound를 CloudFront 관리형 prefix list의 사전 조사로 확정한 실제 식별자에 연결하고 조사 전에는 추정 ID를 사용하지 않는다.
3. **[Ubiquitous]** THE Terraform_Configuration SHALL EC2 Security Group에 사전 조사로 확인한 ALB Security Group을 출발지로 하는 TCP 8080 inbound 규칙을 정의하고 출발지·포트·프로토콜을 plan에서 검증한다.
4. **[Ubiquitous]** THE Terraform_Configuration SHALL 보안 그룹 규칙을 `aws_vpc_security_group_ingress_rule`와 `aws_vpc_security_group_egress_rule` 개별 리소스로 정의한다.
5. **[Unwanted-event]** IF 사전 조사에서 `0.0.0.0/0` SSH 등 과도한 개방 규칙이 발견되면, THEN THE Import_Log SHALL 현행 규칙·위험·축소안을 기록하고 승인 대기 중인 해당 보안 규칙 변경만 apply를 차단하며, 별도 승인 전에는 해당 규칙을 변경하지 않는다. 무관한 리소스의 apply는 허용한다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL 사전 조사로 확인한 모든 inbound·outbound 보안 그룹 규칙을 관리 또는 제외 대상으로 각각 분류하고 각 제외 대상의 사유를 Import_Log에 기록한다.

### Requirement 5: EC2 컴퓨팅과 CodeDeploy 대상

**User Story:** 운영자로서 EC2-A와 평시 중지된 EC2-B를 기존 식별자와 배포 동작을 보존한 채 관리하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확인한 EC2-A와 EC2-B의 실제 인스턴스 식별자를 각각 import하거나 각 대상을 관리 제외하고 제외 사유를 기록한다.
2. **[State-driven]** WHILE `drift_risk_confirmed = true`, THE Terraform_Configuration SHALL AMI·`user_data`·AWS가 관리하는 태그 변경으로 EC2 재생성이 발생하지 않도록 실제 drift 위험이 확인된 항목에 `lifecycle.ignore_changes`를 명시하고 기능 태그 변경은 ignore 대상에서 제외한다.
3. **[Event-driven]** WHEN 유효한 Season_Mode가 `on`으로 apply되면, THE Season_Controller SHALL 사전 조사로 확정한 EC2-B를 running 상태와 기능 태그 `app=boaz-api`로 유지하고 상태·태그 결과를 기록한다.
4. **[Event-driven]** WHEN 유효한 Season_Mode가 `off`로 apply되면, THE Season_Controller SHALL 사전 조사로 확정한 EC2-B를 stopped 상태와 기능 태그 없음으로 유지하고 상태·태그 결과를 기록한다.
5. **[Ubiquitous]** THE Terraform_Configuration SHALL EC2 instance profile에 SSM `GetParameter`·`GetParameters` with decryption, 배포 번들 S3 read, CodeDeploy 에이전트에 필요한 최소 권한만 정의하고 실제 정책·리소스 범위를 plan에서 검증한다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL EC2-A 퍼블릭 DNS 의존성을 제거하기 위한 Elastic IP 도입을 권고안으로 기록하고 승인 전에는 실제 EIP·DNS·origin 변경을 수행하지 않는다.
7. **[Ubiquitous]** THE Terraform_Configuration SHALL `aws_instance`만으로 인스턴스 상태를 관리할 수 없는 경우 `aws_ec2_instance_state`와 ASG 전환안을 비교하고 상태 제어 방식의 선택 근거를 문서화한다.
8. **[Unwanted-event]** IF EC2 상태 전환·기능 태그 변경이 실패하거나 대상 인스턴스 식별자가 확정되지 않으면, THEN THE Season_Controller SHALL 후속 Target Group·CloudFront·RDS 변경을 apply하지 않고 기존 운영 상태와 실패 원인을 기록한다.

### Requirement 6: RDS 데이터베이스

**User Story:** 운영자로서 시즌별 Multi-AZ 전환을 데이터 보호와 비밀번호 보안 조건을 지키며 수행하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 RDS 인스턴스·DB subnet group·parameter group·Security Group을 import하거나 각 대상을 관리 제외하고 사유를 기록한다.
2. **[Event-driven]** WHEN 유효한 Season_Mode가 `on`이면, THE Season_Controller SHALL RDS `multi_az`를 true로 계획하고 해당 변경이 기존 DB의 in-place 변경인지 plan에서 확인한다.
3. **[Event-driven]** WHEN 유효한 Season_Mode가 `off`이면, THE Season_Controller SHALL RDS `multi_az`를 false로 계획하고 해당 변경이 기존 DB의 in-place 변경인지 plan에서 확인한다.
4. **[Ubiquitous]** THE Terraform_Configuration SHALL RDS master password를 코드·변수 파일·plan 출력·로그에 평문으로 두지 않고 `ignore_changes = [password]` 또는 승인된 관리형 시크릿 방식을 사용하며 실제 password diff가 감지되면 apply를 차단한다.
5. **[Ubiquitous]** THE Terraform_Configuration SHALL RDS `deletion_protection = true`와 `skip_final_snapshot = false`를 강제한다.
6. **[Event-driven]** WHEN `multi_az` 변경이 plan에 포함되면, THE Import_Procedure SHALL 해당 변경이 in-place 수정이며 RDS 교체·삭제가 아님을 확인하고 확인 결과를 Import_Log에 기록한다.
7. **[Unwanted-event]** IF RDS 인스턴스·연결 그룹·현재 Multi-AZ 설정을 사전 조사로 확정할 수 없거나 plan에 RDS 교체·삭제가 포함되면, THEN THE Terraform_Configuration SHALL apply를 차단하고 데이터 보호 상태를 변경하지 않는다.

### Requirement 7: S3·CloudFront·Route53·ACM

**User Story:** 운영자로서 애플리케이션 배포 버킷과 웹·API CDN 구성을 현재 동작과 동일하게 재현하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 배포 번들·프론트엔드·지원서 업로드·아카이빙 S3 버킷을 import하거나 각 버킷의 관리 제외 사유를 기록한다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL 각 S3 버킷의 versioning·암호화·퍼블릭 액세스 차단·lifecycle·bucket policy를 `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block`, `aws_s3_bucket_lifecycle_configuration`, `aws_s3_bucket_policy` 등 별도 리소스로 정의한다.
3. **[Optional]** WHERE 운영 승인으로 보존 기간이 정해지면, THE Terraform_Configuration SHALL 배포 번들 버킷의 `deploy-bundle-<sha>.zip` 누적을 줄이는 lifecycle 규칙을 제안하고 적용 전 보존 기준과 삭제 승인자를 문서화한다.
4. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 API·www·dev CloudFront 배포, Route53 레코드, ACM 인증서를 import하거나 관리 제외 사유를 기록하며 미확인 ID·ARN·리전은 import ID로 사용하지 않는다. 검증되지 않은 ID·ARN·리전이 하나라도 import ID로 사용되면 전체 import 작업을 차단한다.
5. **[Unwanted-event]** IF API CloudFront의 origin 수가 정확히 1개가 아니거나 현재 설정을 확인할 수 없으면, THEN THE Terraform_Configuration SHALL 검증 오류를 발생시켜 plan·apply를 차단한다.
6. **[Event-driven]** WHEN Season_Mode가 `on`이고 ALB DNS·리스너 포트가 사전 조사 및 plan에서 유효하면, THE Season_Controller SHALL API CloudFront origin을 Terraform ALB resource attribute의 DNS와 포트 80으로 계획한다.
7. **[Event-driven]** WHEN Season_Mode가 `off`이고 EC2-A origin이 사전 조사로 확정되면, THE Season_Controller SHALL API CloudFront origin을 EC2-A resource attribute의 origin과 포트 8080으로 계획한다.
8. **[Ubiquitous]** THE Terraform_Configuration SHALL 프론트 CloudFront의 SPA 403/404 → `/index.html` 동작과 현행 캐시 정책을 보존하고 plan에서 변경 여부를 검증한다.
9. **[Ubiquitous]** THE Terraform_Configuration SHALL CloudFront용 ACM provider를 인증서 리전에 맞게 분리하고, 인증서 리전·ARN이 AWS CLI 사전 조사로 확정되지 않으면 import·plan·apply를 진행하지 않는다.
10. **[Unwanted-event]** IF S3 버킷·CloudFront 배포·Route53 레코드·ACM 인증서 중 하나라도 실제 식별자 또는 현재 설정을 확정할 수 없거나 origin·인증서 변경이 교체를 유발하면, THEN THE Terraform_Configuration SHALL 해당 변경을 차단하고 조사 결과와 조치 필요성을 기록한다.

### Requirement 8: CodeDeploy·GitHub OIDC와 기존 배포 계약

**User Story:** 운영자로서 인프라 코드화 이후에도 기존 세 애플리케이션 저장소의 배포 workflow를 수정하지 않고 계속 사용하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 CodeDeploy 애플리케이션·배포 그룹을 import하고 대상 태그와 기존 배포 설정을 조사 결과와 동일하게 보존한다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확정한 GitHub OIDC provider·backend 배포 롤·frontend 배포 롤과 연결 정책을 import하고 기존 trust 조건과 권한 범위를 변경하지 않는다.
3. **[Ubiquitous]** THE Terraform_Configuration SHALL backend workflow가 참조하는 CodeDeploy 앱·그룹·S3 버킷 이름·ARN 계약을 기존 workflow와 동일하게 보존한다.
4. **[Ubiquitous]** THE Terraform_Configuration SHALL frontend `deploy-www.yml`과 `deploy-dev.yml`이 참조하는 S3 버킷·CloudFront 배포 ID·AWS 롤 ARN 계약을 기존 workflow와 동일하게 보존한다.
5. **[Ubiquitous]** THE Terraform_Configuration SHALL workflow가 참조할 사전 조사 확정 버킷명·CloudFront 배포 ID·롤 ARN·CodeDeploy 앱/그룹명을 Terraform output으로 노출하고 output과 workflow 참조의 불일치를 검증 실패로 판정하며 Terraform apply도 차단한다.
6. **[Unwanted-event]** IF Terraform 변경으로 기존 workflow 파일 수정이 필요하거나 output 값이 workflow 참조와 다르면, THEN THE Import_Procedure SHALL 해당 변경을 마이그레이션 실패로 보고 apply를 차단하고 리소스 이름·ARN 정의를 재검토한다.
7. **[Event-driven]** WHEN 기존 backend·frontend 배포 workflow의 대표 실행을 완료하면, THE Season_Runbook SHALL CodeDeploy·S3 sync·CloudFront invalidation의 성공 결과와 사용한 계약 값의 일치 여부를 기록한다.

### Requirement 9: SSM 인프라 파라미터와 앱 시크릿

**User Story:** 운영자로서 인프라 식별자는 코드에서 파생시키고 앱 시크릿 값은 Git과 Terraform state에서 보호하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사에서 존재가 확인된 `/boaz/infra/*` 파라미터를 정확히 12개의 Infra_Parameter로 분류하고, 목록 개수가 12개가 아니면 plan·apply를 차단하며 각 값은 관리 리소스 attribute 또는 module output에서 파생한다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL `DB_*`, `JWT_SECRET`, OAuth 클라이언트, `SWAGGER_*` 등을 Secret_Parameter로 분류하고 실제 값의 조회·변경 대상에서 제외한다.
3. **[Ubiquitous]** THE Terraform_Configuration SHALL Secret_Parameter의 존재·타입·KMS 키만 관리하고 실제 값은 `ignore_changes = [value]` 또는 값 미관리 방식으로 제외하며 구성·변수 파일·output·plan·state·로그에 포함하지 않는다.
4. **[Optional]** WHERE 운영 담당자가 SecureString 전환을 승인하면, THE Terraform_Configuration SHALL 앱 시크릿 파라미터를 SecureString과 지정 KMS 키로 관리하는 전환 계획과 롤백 절차를 제공하고 승인 전에는 값을 변경하지 않는다.
5. **[Event-driven]** WHEN 마이그레이션이 완료되고 12개 Infra_Parameter의 참조 관계가 plan에서 검증되면, THE Terraform_Configuration SHALL `/boaz/infra/*` 값을 하드코딩하지 않고 `register-ssm-params.sh`를 폐기 또는 deprecated로 표시한다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL 현행 루트 파라미터 이름을 이번 범위에서 변경하지 않고 `/boaz/app/*` 이관을 후속 과제로 기록한다.
7. **[Unwanted-event]** IF 앱 시크릿 파라미터의 실제 값이 Terraform state·plan·로그에 노출되거나 Infra_Parameter 목록·값의 리소스 attribute 대조가 불일치하면, THEN THE Terraform_Configuration SHALL 조회·plan·apply를 차단하고 노출 여부와 복구 조치를 기록한다.

### Requirement 10: 단일 변수 기반 시즌 전환

**User Story:** 운영자로서 시즌 시작·종료를 스크립트 여러 단계와 콘솔 수동 복구가 아니라 변수 하나와 검토된 apply로 수행하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Season_Controller SHALL Season_Mode 입력을 `off` 또는 `on`으로만 허용하고 그 밖의 입력은 variable validation 실패로 처리해 plan·apply를 실행하지 않는다.
2. **[Event-driven]** WHEN 유효한 Season_Mode가 `off`이면, THE Season_Controller SHALL ALB·listener를 absent로, EC2-B를 stopped·기능 태그 없음으로, Target Group을 EC2-A 단독으로, API CloudFront origin을 EC2-A:8080으로, RDS Multi-AZ를 false로 계획한다.
3. **[Event-driven]** WHEN 유효한 Season_Mode가 `on`이면, THE Season_Controller SHALL ALB·listener(:80)를 present로, EC2-B를 running·`app=boaz-api`로, Target Group을 EC2-A·EC2-B로, API CloudFront origin을 ALB DNS:80으로, RDS Multi-AZ를 true로 계획한다.
4. **[Ubiquitous]** THE Season_Controller SHALL `count`·`for_each`·조건식으로 상태 전환을 표현하고 별도 시즌 shell/Python 스크립트 실행을 요구하지 않는다.
5. **[Event-driven]** WHEN Season_Mode가 `on`으로 apply되면, THE Season_Controller SHALL ALB 생성 → listener·Target Group 연결 → EC2-A/B healthy 확인 → CloudFront origin 변경 순서를 dependency graph와 health precondition으로 표현하고, 모든 target이 healthy가 아니면 origin 변경을 실행하지 않는다.
6. **[Event-driven]** WHEN Season_Mode가 `off`로 apply되면, THE Season_Controller SHALL CloudFront origin을 EC2-A로 복귀시키고 CloudFront 상태가 `Deployed`임을 확인한 뒤에만 ALB 제거를 진행한다.
7. **[Event-driven]** WHEN Season_Mode가 `off` 전환으로 실행되면, THE Season_Runbook SHALL 모든 `off` 전환에 CloudFront origin 복귀 apply → `Deployed` 확인 → ALB 제거 apply의 2단계 절차를 항상 적용하고, `Deployed` 확인 전 ALB 제거 apply를 차단한다.
8. **[Unwanted-event]** IF Target Group healthy 또는 CloudFront `Deployed` 확인이 제한시간 900초 안에 완료되지 않으면, THEN THE Season_Controller SHALL 후속 의존 리소스와 origin 변경을 apply하지 않고 이전에 검증된 운영 상태와 실패 증적을 유지한다.
9. **[Ubiquitous]** THE Season_Controller SHALL 매 시즌 달라지는 ALB DNS를 수동 입력값이 아니라 ALB resource attribute 참조로 연결한다.
10. **[Event-driven]** WHEN Terraform 마이그레이션이 완료되면, THE Infra_Repository SHALL `season-up.sh`, `season-down.sh`, `cf_set_origin.py`, `register-ssm-params.sh`를 삭제하거나 deprecated로 표시한다.
11. **[Ubiquitous]** THE Season_Runbook SHALL 운영 적용 전에 `on` → 검증 → `off` 리허설을 수행하도록 하고 invalid mode 또는 unhealthy precondition 발생 시 origin 변경과 다음 apply를 중지하는 절차를 포함한다.

### Requirement 11: 공통 태그와 이름 보존

**User Story:** 운영자로서 리소스 소유권과 환경을 일관되게 식별하면서 기존 배포 계약을 깨뜨리고 싶지 않다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Terraform_Configuration SHALL provider `default_tags`로 태그를 지원하는 운영 리소스에 `Project=boaz`, `Environment=prod`, `ManagedBy=terraform`, `Repository=BOAZ-website/product-infra`를 적용하고 적용 불가 리소스와 사유를 목록화한다. 해당 목록은 문서화만 하며 최신성 검증이나 apply 차단 조건으로 사용하지 않는다.
2. **[Ubiquitous]** THE Terraform_Configuration SHALL `app=boaz-api` 같은 기능적 태그를 `default_tags`의 공통 태그와 별도 resource/module 입력으로 관리한다.
3. **[Ubiquitous]** THE Terraform_Configuration SHALL AWS CLI 사전 조사로 확인한 기존 리소스 이름을 변경하지 않고 이름 변경·교체가 plan에 포함되면 apply를 차단한다.
4. **[Unwanted-event]** IF 공통 태그 또는 기능 태그 적용이 기존 CodeDeploy 대상·workflow 계약·리소스 식별자를 변경하거나 교체를 유발하면, THEN THE Terraform_Configuration SHALL 해당 plan을 차단하고 예외와 승인 여부를 기록한다.

### Requirement 12: 인프라 CI/CD와 drift 감지

**User Story:** 운영자로서 인프라 변경도 애플리케이션과 같은 PR 리뷰·승인·감사 흐름으로 처리하고 싶다.

#### Acceptance Criteria

1. **[Event-driven]** WHEN Infra_Repository에 PR이 열리면, THE Infrastructure_CI SHALL `terraform fmt -check`, `validate`, plan을 실행하고 각 결과의 성공·실패 상태와 plan 결과를 PR 코멘트로 게시하며, 세 검사가 모두 성공하면 PR을 apply 후보로 명시적으로 표시하고 하나라도 실패하면 apply 후보로 표시하지 않는다.
2. **[Event-driven]** WHEN PR이 `main`에 머지되면, THE Infrastructure_CI SHALL GitHub Environment protection의 수동 승인 게이트가 성공한 뒤에만 `terraform apply`를 실행하고 승인 전 apply를 실행하지 않는다.
3. **[Ubiquitous]** THE Infrastructure_CI SHALL AWS OIDC를 사용하고 장기 액세스 키를 저장·참조하지 않으며 workflow에 `id-token: write` 권한을 명시한다.
4. **[Ubiquitous]** THE Infrastructure_CI SHALL plan 전용 읽기 롤과 apply 전용 쓰기 롤을 분리하고 각 롤의 사전 조사 확정 ARN·권한 범위·사용 workflow를 문서화한다.
5. **[Event-driven]** WHEN 예약된 drift 감지 시점이 되면, THE Infrastructure_CI SHALL 직전 성공 실행 이후 24시간 이내에 최소 한 번 plan을 실행하고 변경이 있거나 plan이 실패하면 담당자에게 알림과 증적을 남긴다.
6. **[Ubiquitous]** THE Terraform_Configuration SHALL plan에 사용되는 민감 변수에 `sensitive = true`를 지정하고 민감 출력값을 생성하지 않는다.
7. **[Unwanted-event]** IF plan 결과에 destroy·replace·Secret_Parameter 실제 값 노출·필수 검사 실패가 있으면, THEN THE Infrastructure_CI SHALL apply를 실행하지 않고 승인자에게 차단 사유와 plan 증적을 명시적으로 알린다.
8. **[Unwanted-event]** IF OIDC provider·plan 롤·apply 롤 또는 Environment 승인 규칙이 사전 조사·결정으로 확정되지 않으면, THEN THE Infrastructure_CI SHALL 운영 apply workflow를 활성화하지 않고 미확정 항목을 결정 필요 문서에 남긴다.

### Requirement 13: 한국어 문서·런북·인수 검증

**User Story:** 운영자로서 담당자가 바뀌어도 import·시즌 전환·장애 복구를 동일한 절차로 재현하고 싶다.

#### Acceptance Criteria

1. **[Ubiquitous]** THE Infra_Repository SHALL 한국어 `README.md`에 저장소 구조, AWS profile `tf`, 확정 Terraform·AWS provider 버전, 초기화·일상 plan/apply 절차, 각 명령의 기대 성공 조건과 실패 시 중지 기준을 기록한다.
2. **[Ubiquitous]** THE Infra_Repository SHALL 한국어 `docs/runbook-season.md`에 사전 점검, `off`·`on`별 apply, Target Group·CloudFront·RDS·API health 검증 커맨드, 실패 시 origin 보존·apply 중지·복구 절차를 기록한다.
3. **[Ubiquitous]** THE Season_Runbook SHALL ALB 상태, Target Group의 모든 target healthy, CloudFront origin domain/port, RDS Multi-AZ, `curl https://api.bigdataboaz.com/actuator/health`의 HTTP 200 결과를 전환 전·중·후에 확인하고 시점별 증적을 기록한다.
4. **[Ubiquitous]** THE Infra_Repository SHALL 한국어 `docs/import-log.md`에 모든 import·관리 제외 대상, AWS CLI로 확정한 식별자 또는 미확정 사유, 조사 시점·근거, plan 결과, 잔여 diff, 승인·복구 조치를 기록한다.
5. **[Ubiquitous]** THE Infra_Repository SHALL 기존 `backend/infra/scripts/README.md`에 신규 저장소 이관 안내와 구 스크립트 폐기 표시를 남긴다.
6. **[Event-driven]** WHEN `envs/prod`의 최종 plan을 실행하면, THE Import_Procedure SHALL 정확히 `No changes. Your infrastructure matches the configuration.`을 확인하고 plan 파일·실행 시점·검증자를 기록한다.
7. **[Event-driven]** WHEN 시즌 시작 리허설(EC2-B 기동·재배포 성공 → `season_capacity = "on"` → `api_origin = "alb"`)을 실행하면, THE Season_Runbook SHALL 재배포 성공, ALB 생성, EC2-A/B healthy, CloudFront origin, RDS Multi-AZ, API health HTTP 200을 확인하고 전환 전·중·후 5xx가 0건임을 증적으로 기록한다.
8. **[Event-driven]** WHEN 시즌 종료 리허설(`api_origin = "ec2"` → `season_capacity = "off"`)을 실행하면, THE Season_Runbook SHALL CloudFront origin 복귀와 `Deployed` 상태를 확인한 뒤 ALB 제거, EC2-B stopped, EC2-A 단독 Target Group, RDS Multi-AZ 복귀, API health HTTP 200을 확인한다.
9. **[Event-driven]** WHEN backend CD workflow를 `workflow_dispatch`로 실행하면, THE Season_Runbook SHALL CodeDeploy 배포가 성공하고 기존 앱·배포 그룹·S3 계약과 일치함을 기록한다.
10. **[Event-driven]** WHEN frontend dev와 main 배포를 실행하면, THE Season_Runbook SHALL 각 S3 sync와 CloudFront invalidation이 성공하고 대상 버킷·배포 ID가 사전 조사 확정 계약과 일치함을 기록한다.
11. **[Ubiquitous]** THE Season_Runbook SHALL 운영 서비스 `www.bigdataboaz.com`과 `api.bigdataboaz.com`의 무중단 제약, 5xx 관측 또는 health 실패 시 apply 중지 기준, origin 복귀·재검증 절차를 명시한다.
12. **[Unwanted-event]** IF 인수 검증 중 API health가 HTTP 200이 아니거나 필수 target이 healthy가 아니거나 CloudFront가 `Deployed`가 아니면, THEN THE Season_Runbook SHALL 인수를 실패 처리하고 운영 apply를 중지하며 마지막으로 검증된 상태와 복구 조치를 기록한다.

## 실행 가능한 Correctness Properties

아래 속성은 수용 기준을 자동화 테스트·plan 검사·대표 AWS 통합 검증으로 확인한다. AWS API 자체의 동작을 100회 반복하는 property test 대신, Terraform 구성·plan에는 property 기반 검사를 적용하고 외부 AWS 리소스에는 단계별 대표 통합 검증을 적용한다.

### P1. 보호 리소스 무교체 불변식

대상: R3-3, R3-7, R12-7, R13-6.

```text
FOR ALL r IN {RDS, EC2, CloudFront, Route53, S3}:
  plan(r).actions ∩ {"delete", "replace"} = ∅
```

검증 예: `terraform plan -out=plan.bin` 후 `terraform show -json plan.bin`에서 대상 resource change의 action에 `delete` 또는 `replace`가 존재하면 실패한다. 위반 시 apply를 실행하지 않는다.

### P2. Import 수렴 속성

대상: R3-1, R3-2, R13-6.

```text
FOR ALL confirmed resource r:
  import(r) THEN plan(envs/prod) = No_Changes_Plan
```

검증 예: Import_Log의 각 확정 리소스 주소와 import ID가 실제 조사 결과에 존재하고, 단계별 plan JSON의 `resource_changes`가 빈 배열 또는 허용된 신규 관리 리소스만 포함하는지 검사한다. 미확인 식별자는 이 속성의 입력으로 사용하지 않는다.

### P3. 시즌 상태 매핑 불변식

대상: R5-3~4, R6-2~3, R10-1~3.

```text
model("off") = {
  alb: absent, listener: absent, ec2_b: stopped,
  ec2_b_functional_tag: absent, targets: {ec2_a},
  api_origin: {ec2_a_domain, 8080}, rds_multi_az: false
}
model("on") = {
  alb: present, listener: {80}, ec2_b: running,
  ec2_b_functional_tag: {"app=boaz-api"}, targets: {ec2_a, ec2_b},
  api_origin: {alb_dns, 80}, rds_multi_az: true
}
```

검증 예: 유효한 세 조합(`off`+`ec2`, `on`+`ec2`, `on`+`alb`)에 대해 Terraform plan JSON을 표준 모델과 비교한다. 허용 값 이외이거나 `off`+`alb` 조합이면 plan 전 실패를 기대한다.

### P4. 시즌 시작 의존성 속성

대상: R10-5, R10-8.

```text
on_order = [alb_created, listener_ready, targets_healthy, cloudfront_origin_updated]
precondition: index(alb_created) < index(listener_ready)
             < index(targets_healthy) < index(cloudfront_origin_updated)
```

검증 예: Terraform graph/리소스 precondition과 리허설 이벤트 로그에서 CloudFront origin 변경 시점에 ALB·listener·모든 target healthy 조건이 먼저 충족되었는지 검사한다. AWS health 상태는 대표 통합 테스트로 확인한다.

### P5. 시즌 종료 안전 순서 속성

대상: R10-6~7, R13-8.

```text
off_order = [cloudfront_origin_reverted, cloudfront_deployed,
              alb_removed, ec2_b_deregistered, ec2_b_stopped]
index(cloudfront_origin_reverted) < index(cloudfront_deployed)
index(cloudfront_deployed) < index(alb_removed)
```

검증 예: Terraform이 전파 대기를 표현하지 못하면 두 단계 apply 런북 실행 기록을 검사하고, `Deployed` 확인 이전 ALB 삭제 시나리오는 실패해야 한다.

### P6. 시크릿 비노출 속성

대상: R2-6, R6-4, R9-2~3, R12-6~7.

```text
FOR ALL s IN Secret_Parameter:
  config_value(s) = absent
  plan_output contains actual_value(s) = false
  git_tracked_files contain actual_value(s) = false
```

검증 예: 저장소 검색·plan 표준 출력·plan JSON을 secret fixture 값과 대조한다. Secret_Parameter의 타입·KMS key·존재만 변경하는 plan은 허용하고, 실제 값 변경·출력은 실패 처리한다.

### P7. 인프라 파라미터 파생 속성

대상: R9-1, R9-5.

```text
FOR ALL p IN Infra_Parameter:
  p.value = reference(managed_resource_attribute)
  p.value != hardcoded_identifier
```

검증 예: Terraform 설정 AST/plan JSON에서 `/boaz/infra/*` 값이 literal이 아닌 resource/module output 참조인지 확인하고, `register-ssm-params.sh`가 실행 경로에 남아 있으면 폐기 검사를 실패시킨다.

### P8. 기존 배포 계약 보존 속성

대상: R8-3~6, R11-3.

```text
workflow_references_after_migration = workflow_references_before_migration
resource_names_and_required_arns are unchanged
```

검증 예: backend `cd.yml`, frontend `deploy-www.yml`, `deploy-dev.yml`의 참조 토큰과 Terraform outputs를 비교하고, 기존 workflow 파일의 diff가 비어 있는지 확인한다. 외부 GitHub Actions·AWS 배포 자체는 각 workflow 대표 실행으로 검증한다.

### P9. OIDC·CI 안전 속성

대상: R8-2, R12-1~5.

```text
FOR ALL deploy jobs:
  long_lived_access_key references = 0
  oidc_permission(id-token: write) = true
PR => fmt_check AND validate AND plan AND plan_comment
main_merge => protected_apply_gate BEFORE apply
scheduled_drift => plan at least daily
```

검증 예: workflow YAML 정적 검사와 GitHub Actions 실행 결과로 확인한다.

### P10. 런북 인수 검증 속성

대상: R13-2~3, R13-7~11.

```text
on_rehearsal.5xx_count = 0
health(before) = 200 AND health(during) = 200 AND health(after) = 200
required_checks = {alb, target_health, cloudfront_origin, rds_multi_az, api_health}
```

검증 예: `aws` 조회 결과와 curl 응답을 Import_Log/리허설 기록에 저장한다. 외부 서비스의 상태는 정해진 전환 전·중·후 대표 실행으로 확인하며 property test로 AWS를 반복 호출하지 않는다.

## 사전 조사 필요 항목

다음 값은 제공된 문서와 저장소만으로 확정할 수 없으므로 Terraform import ID 또는 최종 요구사항으로 추정하지 않는다. AWS CLI는 `--profile tf --region ap-northeast-2`를 사용하고, 시크릿 파라미터 값은 조회하지 않는다.

1. VPC ID, 두 서브넷의 AZ·라우트 테이블 연결, 인터넷 게이트웨이, 관련 route/NACL.
2. EC2-A 인스턴스 ID, SG, IAM instance profile, AMI·user_data·현재 상태.
3. 모든 SG 규칙과 CloudFront managed prefix list의 실제 prefix list ID.
4. RDS `boaz-prod-db`의 instance class·storage·engine minor version·parameter group·subnet group·SG·deletion protection·Multi-AZ 현재값.
5. API CloudFront api CloudFront 배포 ID의 origin·cache policy·behavior·viewer certificate·aliases·현재 단일 origin 여부.
6. www/admin CloudFront 배포 ID와 각 origin·cache/error response 정책.
7. 모든 S3 버킷 이름, region, versioning·encryption·public access block·policy·lifecycle.
8. Route53 hosted zone ID와 `www`, `dev`, `api` 레코드, ACM 인증서 ARN과 인증서 리전.
9. CodeDeploy 서비스 롤·deployment group 세부 설정·실제 배포 config.
10. GitHub frontend secrets `S3_BUCKET_WWW`, `S3_BUCKET_DEV`, `CF_DIST_ID_WWW`, `CF_DIST_ID_DEV`, `AWS_ROLE_ARN`의 실제 값과 AWS 조회 결과 대조.
11. `/boaz/infra/*` 12개와 앱 시크릿 파라미터의 존재·타입·KMS key. 앱 시크릿 값은 조회하지 않는다.
12. Target Group 현재 등록 target·health·health check 설정과 `boaz-alb`가 조사 시점에 존재하는지.

## 결정 필요 항목

1. [확정] State_Backend 락은 S3 native lock(`use_lockfile = true`)으로 확정한다. DynamoDB 락은 활성화하지 않는다.
2. EC2-A Elastic IP 도입 여부와 기존 DNS origin 교체 승인 여부.
3. EC2-B 상태 제어를 `aws_ec2_instance_state`로 구현할지 ASG min=0/1 전환안을 선택할지.
4. 앱 시크릿을 SecureString으로 통일할지, 통일한다면 전환 시점·KMS 키·운영 승인자.
5. Infra_Repository 브랜치 전략을 `dev → main`으로 할지 `main` 단일로 할지.
6. apply용 GitHub Environment 보호 규칙과 승인자.
7. 배포 번들 S3 lifecycle의 보존 기간과 삭제 승인 기준.
8. [확정] 모든 시즌 종료는 `api_origin = "ec2"` apply(origin 복귀) → `Deployed` 확인 → `season_capacity = "off"` apply(ALB 제거)의 2단계 절차를 운영 표준으로 적용한다. 시즌 시작은 EC2-B 재배포 성공 뒤에만 `season_capacity = "on"`을 적용한다.

## 인수 조건(Definition of Done)

1. `envs/prod`의 최종 plan이 `No changes. Your infrastructure matches the configuration.`을 출력한다.
2. 인벤토리의 모든 미확인 항목이 AWS 조사 결과로 확정되거나 관리 제외 사유와 함께 Import_Log에 기록된다.
3. 시즌 시작(`season_capacity = "on"` → `api_origin = "alb"`) → 검증 → 시즌 종료(`api_origin = "ec2"` → `season_capacity = "off"`) 리허설이 성공하고 ALB, target health, CloudFront origin, RDS Multi-AZ, API health를 확인한다.
4. 리허설 전환 전·중·후 API health가 정상이고 5xx가 관측되지 않는다.
5. backend `workflow_dispatch` CodeDeploy 배포가 성공한다.
6. frontend `dev`·`main` 배포가 성공한다.
7. Infra_Repository CI의 fmt/validate/plan PR 흐름, 승인 apply, drift plan이 동작한다.
8. README, Season_Runbook, Import_Log 및 구 스크립트 폐기 표시가 완료된다.
9. 위 조건을 충족하기 전에는 운영 apply를 승인하지 않는다.
