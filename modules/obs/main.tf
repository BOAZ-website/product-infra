# obs 모듈
# 담당 명세서: OBS (docs/wbs/20-obs.md) · 이슈: #48 OBS-01
# 관리 자원: SNS 주제·구독, CloudWatch 경보, 로그 그룹(앱·RDS 90일), Discord 알림 Lambda·실행 역할. CloudFront 지표 경보와 그 SNS 주제는 us-east-1
#
# 파일 구성
# - main.tf: SNS 주제·이메일 구독(서울, us-east-1), 앱 로그 그룹, RDS 로그 그룹
# - alarms.tf: RDS·EC2 경보(서울), CloudFront 경보(us-east-1)
# - Discord 알림 Lambda(OBS-01-06)는 별도 PR에서 추가함(20-obs.md "진행 순서")
#
# - 콘솔로 만든 서울 SNS 주제·구독·로그 그룹·경보 12개는 import함(envs/prod/imports_obs.tf). 현행 값 그대로 적어 plan에 변경이 없어야 함
# - 경보 대상 EC2·RDS는 data source로 조회만 하고 바꾸지 않음(OBS-01-05)
# - 이메일 구독 주소를 나중에 바꾸면 교체로 잡히고 Phase 2 동안 G4에 막힘
# - 새로 만드는 us-east-1 구독은 apply 뒤 수신자가 확인 메일의 링크를 눌러야 활성화됨

# 서울 리전 경보용(RDS·EC2). 기존 주제 import, 정책은 기본 정책 그대로라 적지 않음
resource "aws_sns_topic" "alerts" {
  name         = var.alert_topic_name
  display_name = var.alert_topic_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.group_vars.alert_emails

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value

  # 두 값은 AWS에 없는 Terraform 전용 설정이라 import 뒤 state에 비어 있음. 무시하지 않으면 plan에 변경이 나옴
  lifecycle {
    ignore_changes = [confirmation_timeout_in_minutes, endpoint_auto_confirms]
  }
}

# CloudFront 지표는 us-east-1에만 있어 경보와 주제를 us-east-1에 만듦
resource "aws_sns_topic" "alerts_us_east_1" {
  provider = aws.us_east_1

  name = "${var.name_prefix}-alerts-us-east-1"
}

resource "aws_sns_topic_subscription" "email_us_east_1" {
  provider = aws.us_east_1
  for_each = var.group_vars.alert_emails

  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "email"
  endpoint  = each.value
}

# 앱 로그 그룹(OBS-01-03). 기존 그룹 import(보관 90일, 2026-11-24 30일에서 변경). 삭제되면 로그가 사라지므로 prevent_destroy를 둠
resource "aws_cloudwatch_log_group" "app" {
  name              = var.app_log_group_name
  retention_in_days = var.log_retention_days

  lifecycle {
    prevent_destroy = true
  }
}

# RDS 로그 그룹(OBS-01-07). RDS 로그 내보내기가 쓰는 이름이라 바꾸면 안 됨
# - error: 기존 그룹 import(무기한 보관이었음). slowquery: 새로 만듦. 내보내기는 이 apply 뒤에 콘솔로 켬(docs/wbs/25-rdb.md)
# - obs 그룹에서만 관리하고 database 코드에는 넣지 않음(RDB-01-06)
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(var.rds_log_types)

  name              = "/aws/rds/instance/${var.db_instance_identifier}/${each.key}"
  retention_in_days = var.rds_log_retention_days

  lifecycle {
    prevent_destroy = true
  }
}
