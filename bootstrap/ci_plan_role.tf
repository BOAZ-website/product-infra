# PR plan CI 전용 IAM 역할 (STA-05, docs/wbs/11-sta.md)
#
# - GitHub OIDC provider는 이미 계정에 있고(backend·frontend 배포 역할이 사용) IAM 그룹이 envs/prod로 import함.
#   여기서는 만들지 않고 data source로 참조만 함(같은 URL의 provider는 계정당 하나만 가능)
# - 이 저장소의 pull_request 이벤트에서만 AssumeRole 가능. 포크 PR은 GitHub가 OIDC 토큰을 주지 않음
# - 권한: 읽기 전용(ReadOnlyAccess) + state 조회·잠금 파일 쓰기. apply 권한은 없음(STA-11에서 별도 역할)
# - PR 코드가 이 역할로 실행되므로 데이터 영역 읽기(S3 객체·복호화·시크릿·로그 등)는 명시적으로 거부함

locals {
  # 이 저장소는 2026-07-15 이후 생성돼 GitHub OIDC가 immutable subject 형식(repo:OWNER@OWNER_ID/REPO@REPO_ID:...)을 씀.
  # 이름만 쓴 형식(repo:BOAZ-website/product-infra:...)은 토큰과 맞지 않아 AssumeRole이 실패함.
  # 확인: gh api repos/BOAZ-website/product-infra/actions/oidc/customization/sub 의 sub_claim_prefix
  # (GitHub 소유자·저장소 번호는 공개 정보이며 AWS 식별자가 아님)
  github_oidc_sub_prefix = "repo:BOAZ-website@258640138/product-infra@1377059386"
  prod_state_key         = "envs/prod/terraform.tfstate"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # pull_request 이벤트 토큰만 허용(push·workflow_dispatch·다른 저장소는 불가)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_oidc_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  name                 = "role-terraform-plan-ci"
  description          = "product-infra PR plan CI(read-only). STA-05"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_plan_read_only" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# state 조회·잠금 파일 쓰기 + 데이터 영역 읽기 거부. CI plan 역할과 팀원 읽기 전용 그룹이 공용으로 씀(STA-05·#44)
# 둘 다 "ReadOnlyAccess + 이 정책" 조합이라, 보호 자원 설정은 조회 가능하되 시크릿·S3 객체·로그는 읽지 못함
data "aws_iam_policy_document" "terraform_plan" {
  # state 조회
  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "StateRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/${local.prod_state_key}",
      "${aws_s3_bucket.state.arn}/${local.prod_state_key}.tflock",
    ]
  }

  # S3 자체 잠금(use_lockfile): plan도 state 잠금 파일을 만들고 지움. state 본문 쓰기는 허용하지 않음
  statement {
    sid       = "StateLockFile"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${local.prod_state_key}.tflock"]
  }

  # ReadOnlyAccess에 들어 있는 데이터 영역 읽기 거부(지원서·배포 번들 등 S3 객체, 로그, 시크릿, 암호문 복호화)
  # state 본문·잠금 파일만 NotResource로 예외(조건 키가 아니라 NotResource를 써야 GetObject에 정확히 적용됨)
  statement {
    sid    = "DenyObjectReadOutsideState"
    effect = "Deny"
    actions = [
      "s3:GetObject*",
    ]
    not_resources = [
      "${aws_s3_bucket.state.arn}/${local.prod_state_key}",
      "${aws_s3_bucket.state.arn}/${local.prod_state_key}.tflock",
    ]
  }

  # kms:Decrypt만 막아 평문 시크릿을 차단함. ssm:GetParameter 자체는 막지 않음(IAM 그룹 plan이 파라미터를 읽어야 함)
  statement {
    sid    = "DenyDataPlaneReads"
    effect = "Deny"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "secretsmanager:GetSecretValue",
      "ssm:GetParameterHistory",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:GetQueryResults",
      "logs:StartLiveTail",
      "ec2:GetPasswordData",
      "ec2:GetConsoleOutput",
      "ec2:GetConsoleScreenshot",
      "rds:DownloadDBLogFilePortion",
      "rds:DownloadCompleteDBLogFile",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_plan" {
  name        = "terraform-plan-state-and-deny"
  description = "Terraform plan용 state 접근 + 데이터 영역 읽기 거부. CI 역할·팀원 읽기 전용 그룹 공용"
  policy      = data.aws_iam_policy_document.terraform_plan.json
}

resource "aws_iam_role_policy_attachment" "ci_plan" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = aws_iam_policy.terraform_plan.arn
}

output "ci_plan_role_arn" {
  description = "PR plan CI가 AssumeRole하는 역할 ARN. 저장소 secret AWS_PLAN_ROLE_ARN에 등록(계정 ID가 들어 있어 문서에 적지 않음)"
  value       = aws_iam_role.ci_plan.arn
}
