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
- 조사 실패·미확정·승인 대기 상태는 `docs/import-log.md`, `docs/decisions.md`에 기록합니다.

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
- 부득이한 경우에만 `git commit --no-verify`로 건너뜁니다.

### 언어

- 커밋 메시지·주석·문서·PR 설명은 **한국어**
- 식별자·리소스 이름·타입은 **영어**
