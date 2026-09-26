# product-infra

BOAZ 프로덕트(frontend/backend)의 AWS 인프라를 **Terraform으로 관리**하는 저장소입니다. 리크루팅 시즌 트래픽 대응(EC2 증설 + ALB 구성 전환)을 포함합니다.

기존에 콘솔/스크립트로 운영되던 AWS 리소스를 Terraform으로 import 하여 코드로 관리하는 것이 목표이며, 애플리케이션 저장소(`backend`, `frontend`)와는 분리되어 인프라만 담당합니다.

## 대상 아키텍처 (요약)

```text
Route53 → CloudFront ┬─ (www / admin)  → S3
                     └─ (api)          → EC2-A  ──→ RDS   (평시)

Route53 → CloudFront ┬─ (www / admin)  → S3
                     └─ (api)          → ALB → EC2-A/EC2-B → RDS(Multi-AZ)  (리크루팅 시즌)
```

- 리전: `ap-northeast-2`
- backend: EC2 + CodeDeploy (systemd `boaz.service`)
- frontend/admin: S3 + CloudFront
- 시즌 전환: `season_mode` (`off` / `on`)로 ALB·EC2-B·RDS Multi-AZ 상태를 관리

## 저장소 구조

```text
product-infra/
├── bootstrap/                # Terraform state 저장 기반 (S3 state bucket 등). 최초 1회.
├── envs/
│   └── prod/                 # 운영 환경 root (backend/provider/변수)
├── modules/                  # 재사용 모듈 (network, compute, database, storage, cdn, deploy, iam, params)
├── docs/                     # import 근거, 시즌 전환 절차, 검증 증적
├── .github/                  # 워크플로우 및 협업 템플릿
└── .kiro/specs/              # 마이그레이션 스펙(requirements/design/tasks)
```

> 상세 설계와 작업 목록은 `.kiro/specs/product-infra-migration/`을 참고하세요.

## 사전 준비

- Terraform (CI 기준 버전: `1.9.8`)
- AWS CLI + 자격증명 프로파일 (조사/실행용, 예: `tf`)
- 커밋 메시지 훅 활성화 (클론 후 1회)

```bash
git config core.hooksPath .githooks
```

## 자주 쓰는 명령

```bash
terraform fmt -recursive                 # 포맷
terraform -chdir=envs/prod init          # 초기화 (backend 설정 필요)
terraform -chdir=envs/prod validate      # 검증
terraform -chdir=envs/prod plan          # 계획 확인
```

CI는 자격증명 없이 `fmt -check` / `validate`(`-backend=false`) / `tflint`만 수행합니다. 실제 `plan`/`apply`/`drift`는 OIDC role과 backend가 확정된 뒤 별도 워크플로우에서 다룹니다.

## 안전 원칙

- 보호 리소스(RDS, S3, CloudFront 등)는 `prevent_destroy`로 관리하며, plan에 `delete`/`replace`가 있으면 승인 없이 apply하지 않습니다.
- AWS 식별자·현재 설정이 확정되지 않은 상태에서 추정값으로 import/apply하지 않습니다.
- secret/password 값은 코드·tfvars·plan·로그에 두지 않습니다.
- 조사 실패·미확정·승인 대기 상태는 `docs/records/import-log.md`, `docs/records/decisions.md`에 기록합니다.

## 보안 정보 공개 금지

이 저장소는 **공개 저장소**다. 코드·문서·커밋 메시지·PR·이슈·코멘트 어디에도 아래 정보를 적지 않는다.

| 구분 | 금지 대상 | 허용 위치 |
| --- | --- | --- |
| 절대 금지 | 공인 IP 주소(개인·사무실·서버 모두, EC2 퍼블릭 DNS 포함), SSH 허용 IP, 비밀번호·토큰·시크릿 값, AWS 액세스 키, 개인 키, 개인 계정명(IAM 사용자명 등) | 없음 |
| 제한 | AWS 계정 ID, 계정 ID가 들어간 ARN, 자원 ID(VPC·서브넷·보안 그룹·인스턴스·EIP·CloudFront 배포·Route53 영역 등) | `docs/records/`(조사·import 기록)에만 |
| 허용 | 자원 이름(버킷명·롤 이름·Target Group 이름 등), 사설 IP 대역(`10.0.0.0/16` 등), 리전 | 어디든 |

- 다른 문서에는 역할명으로 쓴다. 예: "EC2-A", "api CloudFront 배포", "운영진 개인 IP 2개"
- 이미지·PDF·압축·오피스 문서 같은 바이너리 파일은 내용을 자동 검사할 수 없으므로 이 저장소에 올리지 않는다. 필요하면 노션에 첨부하되, 첨부 전에 이 규칙대로 민감 정보를 지우거나 가린다(노션 첨부물도 공개 범위를 벗어날 수 있음).
- 조사할 때 알게 된 값도 위 규칙을 따른다. 필요하면 AWS에서 직접 조회한다.
- 자동 검사는 세 겹이다. 걸리면 값을 지우거나 역할명으로 바꾼다. 훅을 건너뛰지 않는다.
  - GitHub push protection: 알려진 키·토큰 형식이 든 커밋은 push 자체가 거부된다(저장소 설정). secret scanning도 켜져 있어 저장소 전체를 상시 검사한다
  - gitleaks(CI): git 이력 전체에서 비밀번호·토큰·키를 찾는다
  - `scripts/check-sensitive.sh`(CI·커밋 전 훅 `.githooks/pre-commit`): 기성 도구가 모르는 이 저장소 규칙(공인 IP, EC2 퍼블릭 DNS, 계정 ID, 자원 ID)과 키=값 형태 자격 증명을 검사한다. 회귀 테스트는 `scripts/test-check-sensitive.sh`
- 실수로 올렸다면 즉시 인프라 리드에게 알린다. 파일에서 지워도 git 이력에는 남으므로 이력 정리가 필요하다.

## 협업 규약

BOAZ 공통 규약을 따릅니다.

### 브랜치

- `dev` → `main` 모델. 기능 PR의 base는 `dev`입니다.
- base가 `main`이면 워크플로우가 경고 코멘트를 남깁니다. (`hotfix/*`, `release/*`, `dev` → `main`은 예외)

### 이슈 / PR 제목

`[Type] 내용` 양식을 사용합니다. (예: `[Feat] network module 구현`)

- 허용 Type: `[Feat]` `[Fix]` `[Docs]` `[Style]` `[Refactor]` `[Test]` `[Chore]` `[Hotfix]`

### 커밋 메시지

`type: 내용 (#이슈번호)` 양식을 강제합니다. (예: `feat: bootstrap state bucket 구성 (#3)`)

- 허용 type(소문자): `feat fix docs style refactor test chore`
- 끝에 `(#이슈번호)`가 없으면 커밋이 거부됩니다.
- 훅은 건너뛰지 않습니다(`git commit --no-verify` 금지). 커밋 메시지 훅과 함께 민감 정보 검사 훅도 우회되기 때문입니다.

### 언어

- 커밋 메시지·주석·문서·PR 설명은 **한국어**
- 식별자·리소스 이름·타입은 **영어**
