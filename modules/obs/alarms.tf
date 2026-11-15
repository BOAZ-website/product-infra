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
