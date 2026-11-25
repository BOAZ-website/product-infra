# Discord 경보 전달 Lambda(OBS-01-06, 이슈 #115)
# - 서울 Lambda 1개를 서울·us-east-1 두 경보 주제가 구독함. 구독 자원은 주제가 있는 리전에, 호출 권한은 서울에 주제마다 1개
# - Discord 전달이 실패하면 실패 시 대상(on-failure destination)이 이메일 전용 주제로 원래 이벤트를 넘김
#   경보 주제(alerts)를 실패 대상으로 쓰면 실패 메시지가 다시 Lambda로 들어가므로 따로 만듦
# - 웹훅 URL은 SSM SecureString(수동 등록, Terraform 관리 밖)을 실행 시 읽음. 값을 state에 넣지 않음
# - 모두 새로 만드는 자원임. 함수·로그 그룹 이름을 바꾸면 교체가 되어 G4에 막히므로 처음부터 확정함
# - 되돌리기: 콘솔에서 두 주제의 SNS→Lambda 구독을 끊고 당일 기록(20-obs.md "되돌리기")

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  discord_function_name  = "${var.name_prefix}-discord-notify"
  discord_log_group_name = "/aws/lambda/${local.discord_function_name}"
  discord_webhook_parameter_arn = join("", [
    "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter",
    var.discord_webhook_parameter_name,
  ])

  # Lambda를 호출하는 경보 주제. 키는 구독·권한 자원 주소에 씀
  discord_source_topics = {
    seoul     = aws_sns_topic.alerts.arn
    us_east_1 = aws_sns_topic.alerts_us_east_1.arn
  }
}

# 저장소 소스를 zip으로 묶음(decisions.md "Discord 알림 Lambda 코드 위치"). 파일 권한을 고정해 OS마다 해시가 달라지지 않게 함
data "archive_file" "discord_notify" {
  type             = "zip"
  source_file      = "${path.module}/lambda/discord_notify/handler.py"
  output_path      = "${path.root}/.terraform/archive/discord_notify.zip"
  output_file_mode = "0644"
}

# 함수보다 먼저 만듦. Lambda가 자동으로 만들면 무기한 보관이 됨
resource "aws_cloudwatch_log_group" "discord_notify" {
  name              = local.discord_log_group_name
  retention_in_days = var.lambda_log_retention_days
}

# --- 실패 시 대상: 이메일 전용 주제(서울) ---

resource "aws_sns_topic" "alert_failures" {
  name = "${var.name_prefix}-alert-delivery-failures"
}

# 경보 주제와 같은 그룹 주소. apply 직후 그룹 소유자가 확인 메일을 승인해야 활성화됨(3일 안에 승인하지 않으면 만료)
resource "aws_sns_topic_subscription" "alert_failures_email" {
  for_each = var.group_vars.alert_emails

  topic_arn = aws_sns_topic.alert_failures.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- 실행 역할 ---

# 정책은 jsonencode로 씀(mock provider 테스트에서 aws_iam_policy_document data가 JSON을 만들지 않음)
resource "aws_iam_role" "discord_notify" {
  name        = "${local.discord_function_name}-role"
  description = "Discord 경보 전달 Lambda 실행 역할(OBS-01-06)"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "discord_notify" {
  name = "discord-notify"
  role = aws_iam_role.discord_notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.discord_notify.arn}:*"
      },
      {
        Sid      = "ReadWebhookParameter"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = local.discord_webhook_parameter_arn
      },
      {
        # AWS 관리형 키(alias/aws/ssm)로 암호화된 값 복호화. SSM을 거친 요청만 허용함
        Sid       = "DecryptViaSsm"
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${data.aws_region.current.region}.amazonaws.com" } }
      },
      {
        Sid      = "PublishDeliveryFailures"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alert_failures.arn
      },
    ]
  })
}

# --- 함수 ---

resource "aws_lambda_function" "discord_notify" {
  function_name    = local.discord_function_name
  description      = "SNS 경보를 Discord 웹훅으로 전달(OBS-01-06)"
  role             = aws_iam_role.discord_notify.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.discord_notify.output_path
  source_code_hash = data.archive_file.discord_notify.output_base64sha256
  timeout          = 15 # Discord HTTP 제한 3초 × 2번 + Retry-After 대기 상한 5초보다 크게
  memory_size      = 128

  environment {
    variables = {
      WEBHOOK_PARAMETER_NAME = var.discord_webhook_parameter_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.discord_notify, aws_iam_role_policy.discord_notify]
}

# 비동기 재시도 0회(기본 2회면 실패 메일이 몇 분 늦어짐). 재시도는 코드 안에서 1번만 함
resource "aws_lambda_function_event_invoke_config" "discord_notify" {
  function_name          = aws_lambda_function.discord_notify.function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = aws_sns_topic.alert_failures.arn
    }
  }
}

# --- 경보 주제 → Lambda ---

resource "aws_lambda_permission" "discord_notify" {
  for_each = local.discord_source_topics

  statement_id  = "AllowSns-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_notify.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value
}

resource "aws_sns_topic_subscription" "discord_seoul" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_notify.arn

  depends_on = [aws_lambda_permission.discord_notify]
}

resource "aws_sns_topic_subscription" "discord_us_east_1" {
  provider = aws.us_east_1

  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_notify.arn

  depends_on = [aws_lambda_permission.discord_notify]
}
