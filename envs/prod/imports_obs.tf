# obs 그룹 import 블록 전용 파일 (담당 명세서: OBS, docs/wbs/20-obs.md)
# - 콘솔로 만든 기존 자원만 import함. CloudFront 5xx 경보와 us-east-1 SNS 주제·구독은 새로 만듦
# - 자원 ID는 코드에 직접 쓰지 않음(공개 저장소 규칙). 구독 ID는 그룹 값 obs.alert_subscription_ids
# - 작업 절차: docs/guides/import-procedure.md

locals {
  obs_alert_topic_arn = "arn:aws:sns:ap-northeast-2:${var.expected_account_id}:${local.obs_alert_topic_name}"
}

import {
  to = module.obs.aws_sns_topic.alerts
  id = local.obs_alert_topic_arn
}

# 구독 ARN = 주제 ARN + ":" + 구독 ID. 키는 alert_emails와 같음
import {
  for_each = local.group_vars.obs.alert_subscription_ids
  to       = module.obs.aws_sns_topic_subscription.email[each.key]
  id       = "${local.obs_alert_topic_arn}:${each.value}"
}

import {
  to = module.obs.aws_cloudwatch_log_group.app
  id = "/boaz/api/application"
}

# RDS 오류 로그 그룹(RDS 로그 내보내기가 만든 기존 그룹). slowquery는 없어서 새로 만듦
import {
  to = module.obs.aws_cloudwatch_log_group.rds["error"]
  id = "/aws/rds/instance/${local.obs_db_instance_identifier}/error"
}

import {
  for_each = local.obs_existing_alarms
  to       = module.obs.aws_cloudwatch_metric_alarm.existing[each.key]
  id       = each.value.name
}
