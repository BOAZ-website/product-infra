# api 헬스체크(OBS-01-08, 이슈 #118)
# - EventBridge 규칙(서울, 1분 주기) → Lambda가 api CloudFront 도메인의 /actuator/health를 부름 → 사용자 지정 지표(성공 1, 실패 0) → 경보
# - 경보는 1분 단위 3번 연속 실패면 울림. 배포 때 약 50초 중단과 일정 실행 시각의 흔들림이 겹쳐 2번 연속 실패가 나는 것을 피함
# - 점검이 멈춰 지표가 비는 것도 실패로 봄(treat_missing_data = "breaching")
# - EventBridge Scheduler는 쓰지 않음(IAM 역할이 하나 더 필요함)
# - 모두 새로 만드는 자원임. 이름을 바꾸면 교체가 되어 G4에 막히므로 처음부터 확정함
# - 되돌리기: 경보 동작을 먼저 끈 뒤 EventBridge 규칙을 끔(규칙만 끄면 데이터 누락으로 경보가 울림). 당일 기록(20-obs.md "되돌리기")

locals {
  health_check_function_name  = "${var.name_prefix}-api-health-check"
  health_check_log_group_name = "/aws/lambda/${local.health_check_function_name}"
  health_check_namespace      = "BOAZ/HealthCheck"
  health_check_metric_name    = "ApiHealthy"
}

data "archive_file" "health_check" {
  type             = "zip"
  source_file      = "${path.module}/lambda/health_check/handler.py"
  output_path      = "${path.root}/.terraform/archive/health_check.zip"
  output_file_mode = "0644"
}

# 함수보다 먼저 만듦. Lambda가 자동으로 만들면 무기한 보관이 됨
resource "aws_cloudwatch_log_group" "health_check" {
  name              = local.health_check_log_group_name
  retention_in_days = var.lambda_log_retention_days
}

# --- 실행 역할 ---

resource "aws_iam_role" "health_check" {
  name = "${local.health_check_function_name}-role"
  # IAM 역할 설명은 라틴 문자만 허용됨(한글 불가)
  description = "Execution role for the api health check Lambda (OBS-01-08)"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "health_check" {
  name = "health-check"
  role = aws_iam_role.health_check.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.health_check.arn}:*"
      },
      {
        # PutMetricData는 자원 단위로 제한할 수 없어 이름공간 조건으로 좁힘
        Sid       = "PutHealthMetric"
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = local.health_check_namespace } }
      },
    ]
  })
}

# --- 함수 ---

resource "aws_lambda_function" "health_check" {
  function_name    = local.health_check_function_name
  description      = "api /actuator/health 1분 점검(OBS-01-08)"
  role             = aws_iam_role.health_check.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.health_check.output_path
  source_code_hash = data.archive_file.health_check.output_base64sha256
  timeout          = 10 # HTTP 제한 5초 + 지표 쓰기보다 크게, 1분 주기보다 충분히 작게
  memory_size      = 128

  environment {
    variables = {
      HEALTH_CHECK_URL = var.health_check_url
      METRIC_NAMESPACE = local.health_check_namespace
      METRIC_NAME      = local.health_check_metric_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.health_check, aws_iam_role_policy.health_check]
}

# 비동기 재시도 0회. 재시도하면 다음 1분 점검과 겹쳐 지표가 두 번 쌓일 수 있음. 실패한 회차는 지표가 비어 경보에서 실패로 셈
resource "aws_lambda_function_event_invoke_config" "health_check" {
  function_name          = aws_lambda_function.health_check.function_name
  maximum_retry_attempts = 0
}

# --- 1분 일정 ---

resource "aws_cloudwatch_event_rule" "health_check" {
  name                = local.health_check_function_name
  description         = "api health check every minute (OBS-01-08)"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "health_check" {
  rule = aws_cloudwatch_event_rule.health_check.name
  arn  = aws_lambda_function.health_check.arn
}

resource "aws_lambda_permission" "health_check" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check.arn
}

# --- 경보 ---

# apply 직후 지표가 쌓이기 전 1~2분은 "데이터 없음 = 실패"로 경보가 한 번 울렸다가 복구될 수 있음
resource "aws_cloudwatch_metric_alarm" "api_health" {
  alarm_name = "${var.name_prefix}-api-health-check-failed"
  # 첫 줄은 Discord 메시지의 요약, 둘째 줄부터는 "먼저 볼 것"으로 표시됨(Discord Lambda handler.py)
  alarm_description = join("\n", [
    "api 헬스체크(/actuator/health)가 3분 연속 실패함. 앱이 멈췄거나 CloudFront·WAF에서 막힘 (OBS-01-08)",
    "헬스체크 Lambda 로그(/aws/lambda/${local.health_check_function_name})에서 실패 사유(HTTP 코드, 연결 실패) 확인",
    "502·504 경보가 함께 울렸으면 EC2-A 앱 상태(서비스·CodeDeploy 배포 중인지) 확인",
    "WAF 차단 경보가 함께 울렸으면 헬스체크 요청이 막혔는지 WAF 샘플 요청 확인",
    "점검만 멈춘 경우(Lambda 오류, 지표 없음)는 앱 장애가 아님. 경보 기록과 Lambda 오류 확인",
  ])
  namespace           = local.health_check_namespace
  metric_name         = local.health_check_metric_name
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  depends_on = [aws_cloudwatch_event_target.health_check]
}
