# CloudWatch 경보(OBS-01-02, OBS-01-04)
# - 경보가 울리면(ALARM)과 회복되면(OK) 모두 SNS로 보냄
# - 임계값 근거: RDS 여유 메모리는 decisions.md "경보 수신 이메일·임계값"(50MB). 나머지는 초기 제안값이며 구축 중 알림 빈도를 보고 조정함
# - 평시에는 ALB가 없어 ALB·Target Group 경보는 만들지 않음. 헬스체크·5xx는 CloudFront 지표로 대체함

# 경보 대상 조회(OBS-01-05: 조회만 하고 바꾸지 않음)
data "aws_instance" "ec2_a" {
  filter {
    name   = "tag:Name"
    values = [var.ec2_a_name]
  }
}

data "aws_db_instance" "main" {
  db_instance_identifier = var.db_instance_identifier
}

locals {
  alarm_actions    = [aws_sns_topic.alerts.arn]
  alarm_actions_us = [aws_sns_topic.alerts_us_east_1.arn]

  # 초기 제안값(PO 확인 대상)
  rds_free_storage_threshold_bytes = 2 * 1024 * 1024 * 1024 # 2GiB. 할당 20GB의 약 10%
  rds_cpu_threshold_percent        = 80
  cloudfront_5xx_threshold_percent = 10
}

# --- RDS ---

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  alarm_name          = "${var.name_prefix}-rds-freeable-memory-low"
  alarm_description   = "RDS 여유 메모리가 임계값 아래로 10분간 유지됨(OBS-01-02)"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = data.aws_db_instance.main.db_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_freeable_memory_threshold_bytes
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  alarm_description   = "RDS 남은 저장 공간이 임계값 아래로 떨어짐(OBS-01-04)"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = data.aws_db_instance.main.db_instance_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = local.rds_free_storage_threshold_bytes
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU 사용률이 임계값을 넘은 상태로 15분간 유지됨(OBS-01-04)"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = data.aws_db_instance.main.db_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.rds_cpu_threshold_percent
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- EC2 ---
# 상태 검사 경보는 EC2-A만 만듦. EC2-B는 평시 중지 상태라 지표가 없음
# EC2-A가 멈추면 지표가 끊기므로 데이터 없음을 경보로 봄(breaching)

resource "aws_cloudwatch_metric_alarm" "ec2_a_status_check" {
  alarm_name          = "${var.name_prefix}-ec2-a-status-check-failed"
  alarm_description   = "EC2-A 상태 검사 실패 또는 지표 끊김이 2분간 유지됨(OBS-01-04)"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = data.aws_instance.ec2_a.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
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
