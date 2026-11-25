# CloudWatch 경보(OBS-01-02, OBS-01-04)
# - EC2·RDS 경보 12개는 콘솔로 이미 만든 것을 import함. 현행 설정(회복 알림은 RDS 저장 공간·여유 메모리만) 그대로 둠
# - 평시에는 ALB가 없어 ALB·Target Group 경보는 만들지 않음. 헬스체크·5xx는 CloudFront 지표로 새로 만듦

# 경보 대상 조회(OBS-01-05: 조회만 하고 바꾸지 않음)
# EC2-B는 평시 중지 상태라 상태 조건 없이 Name 태그로만 찾음
data "aws_instance" "ec2" {
  for_each = var.ec2_names

  filter {
    name   = "tag:Name"
    values = [each.value]
  }
}

data "aws_db_instance" "main" {
  db_instance_identifier = var.db_instance_identifier
}

locals {
  alarm_actions    = [aws_sns_topic.alerts.arn]
  alarm_actions_us = [aws_sns_topic.alerts_us_east_1.arn]

  alarm_target_dimensions = merge(
    { for k, instance in data.aws_instance.ec2 : k => { InstanceId = instance.id } },
    { rds = { DBInstanceIdentifier = data.aws_db_instance.main.db_instance_identifier } },
  )

  # 새로 만드는 CloudFront 5xx 경보 임계값. 초기 제안값이며 구축 중 알림 빈도를 보고 조정함
  cloudfront_5xx_threshold_percent = 10
}

# --- 기존 경보 12개(EC2·RDS, import) ---
# 정의는 root(envs/prod/obs.tf의 local.obs_existing_alarms)에 있음. 현행 값 그대로라 이름·조건을 바꾸면 plan에 변경이 생김

resource "aws_cloudwatch_metric_alarm" "existing" {
  for_each = var.existing_alarms

  alarm_name          = each.value.name
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = merge(local.alarm_target_dimensions[each.value.target], each.value.extra_dimensions)
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  comparison_operator = each.value.operator
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = local.alarm_actions
  ok_actions          = each.value.ok_actions ? local.alarm_actions : []
}

# --- CloudFront (us-east-1) ---
# 헬스체크 대용: api 배포의 5xx 비율. origin(EC2-A)이 응답하지 않으면 502·504로 잡힘
# 요청이 없는 구간은 데이터 없음 → 정상으로 봄(notBreaching)

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  provider = aws.us_east_1
  for_each = var.group_vars.distribution_ids

  alarm_name          = "${var.name_prefix}-cloudfront-${each.key}-5xx-rate-high"
  alarm_description   = "CloudFront ${each.key} 배포의 5xx 비율이 임계값을 넘은 상태로 10분간 유지됨(OBS-01-04)"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  dimensions          = { DistributionId = each.value, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.cloudfront_5xx_threshold_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions_us
  ok_actions          = local.alarm_actions_us
}

# --- api CloudFront 추가 지표와 502·504·WAF 차단 경보(OBS-01-09, 이슈 #118) ---
# - 추가 지표는 obs에서만 관리함. cdn 코드에는 선언하지 않음(같은 자원을 두 번 선언하면 충돌). 배포 자원은 바꾸지 않음
# - 추가 지표는 켠 시점부터만 수집됨. 지표 8개 × 월 $0.30
# - 새 경보는 데이터가 쌓이기 전에 만들고 요청이 없는 구간도 있어 데이터 없음은 정상으로 봄(notBreaching)
# - 기존 5xx 비율 경보(위)는 시즌 뒤까지 유지함(decisions.md "api 5xx 경보 교체 방식")

locals {
  api_distribution_id = var.group_vars.distribution_ids["api"]
  # web_acl_id는 WAFv2 웹 ACL ARN(arn:aws:wafv2:us-east-1:<계정>:global/webacl/<이름>/<ID>). 지표 차원에는 이름을 씀
  api_web_acl_name = split("/", data.aws_cloudfront_distribution.api.web_acl_id)[2]
}

resource "aws_cloudfront_monitoring_subscription" "api" {
  provider = aws.us_east_1

  distribution_id = local.api_distribution_id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

# 연결된 웹 ACL을 찾으려고 조회만 함. 자원 ID를 코드에 적지 않음
data "aws_cloudfront_distribution" "api" {
  provider = aws.us_east_1

  id = local.api_distribution_id
}

# 건수 = (502 비율 + 504 비율) ÷ 100 × 요청 수. 근사값이라 실제 1건이 0.97처럼 나올 수 있어 기준은 0.5 이상
resource "aws_cloudwatch_metric_alarm" "cloudfront_api_502_504" {
  provider = aws.us_east_1

  alarm_name = "${var.name_prefix}-cloudfront-api-502-504-count"
  alarm_description = join("\n", [
    "api CloudFront가 502·504를 응답함. 앱(EC2-A, 시즌에는 ALB)이 응답하지 못함 (OBS-01-09)",
    "CodeDeploy 배포 직후라면 재시작 중 502일 수 있음. 헬스체크 경보가 함께 울렸는지 확인",
    "앱 로그 그룹(/boaz/api/application)에서 같은 시각의 오류·재시작 기록 확인",
    "EC2-A 상태 검사·CPU·메모리 경보가 함께 울렸는지 확인",
  ])
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 0.5
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions_us
  ok_actions          = local.alarm_actions_us

  metric_query {
    id          = "count"
    expression  = "(rate502 + rate504) / 100 * requests"
    label       = "502·504 건수"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { rate502 = "502ErrorRate", rate504 = "504ErrorRate" }
    content {
      id = metric_query.key
      metric {
        namespace   = "AWS/CloudFront"
        metric_name = metric_query.value
        dimensions  = { DistributionId = local.api_distribution_id, Region = "Global" }
        stat        = "Average"
        period      = 300
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "Requests"
      dimensions  = { DistributionId = local.api_distribution_id, Region = "Global" }
      stat        = "Sum"
      period      = 300
    }
  }

  depends_on = [aws_cloudfront_monitoring_subscription.api]
}

# WAF 요청 수 제한 규칙(IP당 5분 200건) 차단. 정상 사용자가 막혔는지는 WAF 샘플 요청·로그로 확인함
resource "aws_cloudwatch_metric_alarm" "waf_api_rate_limit" {
  provider = aws.us_east_1

  alarm_name = "${var.name_prefix}-waf-api-rate-limit-blocked"
  alarm_description = join("\n", [
    "api WAF 요청 수 제한 규칙(RateLimitPerIP, IP당 5분 200건)이 요청을 막음 (OBS-01-09)",
    "WAF 콘솔 → api 웹 ACL → 샘플 요청에서 막힌 IP·경로 확인",
    "관리자·평가 화면 경로이고 운영진 IP로 보이면 정상 사용자 차단(2026-06-28 사례). 프론트엔드 재조회 여부와 기준 상향 검토",
    "취약점 탐색·봇 요청이면 조치 없음",
  ])
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = local.api_web_acl_name, Rule = "RateLimitPerIP" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions_us
  ok_actions          = local.alarm_actions_us
}
