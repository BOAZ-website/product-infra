# obs 모듈
# 담당 명세서: OBS (docs/wbs/20-obs.md) · 이슈: #48 OBS-01
# 관리 자원: SNS 주제·구독, CloudWatch 경보, 로그 그룹(30일), Discord 알림 Lambda·실행 역할. CloudFront 지표 경보와 그 SNS 주제는 us-east-1
#
# 파일 구성
# - main.tf: SNS 주제·이메일 구독(서울, us-east-1), 앱 로그 그룹
# - alarms.tf: RDS·EC2 경보(서울), CloudFront 경보(us-east-1)
# - Discord 알림 Lambda(OBS-01-06)는 별도 PR에서 추가함(20-obs.md "진행 순서")
#
# - 기존 자원은 data source로 조회만 하고 바꾸지 않음(OBS-01-05). plan에는 create만 나와야 함
# - 이메일 구독 주소를 나중에 바꾸면 교체로 잡히고 Phase 2 동안 G4에 막힘. 처음부터 정확한 주소로 만듦
# - 이메일 구독은 apply 뒤 수신자가 확인 메일의 링크를 눌러야 활성화됨

# 서울 리전 경보용(RDS·EC2)
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.group_vars.alert_emails

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
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

# 앱 로그 그룹(OBS-01-03). Agent가 먼저 로그를 보내면 보관 기간 무기한으로 자동 생성되므로 apply를 Agent 설정보다 먼저 함
resource "aws_cloudwatch_log_group" "app" {
  name              = var.app_log_group_name
  retention_in_days = var.log_retention_days
}
