# obs 그룹: 모니터링·경보(SNS, CloudWatch 경보, Discord 알림 Lambda)
# 담당 명세서: OBS (docs/wbs/20-obs.md)
#
# - 이 파일은 obs 그룹 담당만 수정함. 공통 파일(versions.tf, providers.tf, backend.tf)은 STA 담당만 수정
# - module "obs" 호출과 그룹 전용 variable·locals만 둠. resource·data는 modules/obs/에 작성
# - 콘솔로 이미 만든 로그 그룹·SNS 주제·구독·경보 12개는 import함(imports_obs.tf). CloudFront 5xx 경보와 그 SNS 주제(us-east-1)만 새로 만듦
# - 경보 수신 이메일은 코드에 적지 않고 SSM 그룹 값(local.group_vars.obs.<키>)으로 받음(docs/guides/import-procedure.md 1-1절)
# - Discord 웹훅 URL은 시크릿이라 그룹 값에 넣지 않음. 수동 등록한 SecureString을 Lambda가 실행 시 읽음(OBS-01-06)
# - 작업 절차: docs/guides/import-procedure.md

locals {
  # 기존 SNS 주제 이름(import id 조립에도 씀)
  obs_alert_topic_name = "boaz-alerts"

  # RDS 인스턴스 식별자. 경보 대상 조회와 RDS 로그 그룹 이름(import id 포함)에 같이 씀
  obs_db_instance_identifier = "boaz-prod-db"

  # 기존 경보 12개. 이름·설명·조건은 현행 값 그대로(describe-alarms, 2026-11-15)
  # - 이름은 import id라 바꾸면 교체가 됨. 공백·한글도 현행 그대로 둠
  # - target: 지표 차원 대상. ec2_a·ec2_b는 InstanceId(Name 태그로 조회), rds는 DBInstanceIdentifier
  # - 생략한 값: datapoints_to_alarm·description null, treat_missing_data "missing"
  # - 정상 복구 알림(ok_actions)은 모든 경보에 켬(2026-11-25, #115). 콘솔 현행은 RDS 경보 2개만 켜져 있었음
  obs_existing_alarms = {
    ec2_a_status    = { name = "EC2-A-StatusCheckFailed", description = "EC2-A-StatusCheckFailed 발생", target = "ec2_a", namespace = "AWS/EC2", metric = "StatusCheckFailed", statistic = "Average", period = 300, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanOrEqualToThreshold", threshold = 1 }
    ec2_b_status    = { name = "EC2 - B -  StatusCheckFailed", description = "EC2 - B - StatusCheckFailed 1 이상 ", target = "ec2_b", namespace = "AWS/EC2", metric = "StatusCheckFailed", statistic = "Average", period = 300, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanOrEqualToThreshold", threshold = 1 }
    ec2_a_cpu       = { name = "EC2-A-CPU 과부하", description = "EC2 - A - CPU 과부하 ( 80% 초과 )", target = "ec2_a", namespace = "AWS/EC2", metric = "CPUUtilization", statistic = "Average", period = 300, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanOrEqualToThreshold", threshold = 80 }
    ec2_b_cpu       = { name = "EC2 - B - CPU 과부하", description = "EC2 - B - CPU 과부하 ( 80% 초과 )", target = "ec2_b", namespace = "AWS/EC2", metric = "CPUUtilization", statistic = "Average", period = 600, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanOrEqualToThreshold", threshold = 80 }
    ec2_a_memory    = { name = "EC2-A-Memory-80 초과", description = "EC2-A-Memory-80 초과", target = "ec2_a", namespace = "BOAZ/Backend", metric = "mem_used_percent", statistic = "Average", period = 600, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanOrEqualToThreshold", threshold = 80 }
    ec2_b_memory    = { name = "EC2-B-메모리 과부하", description = "EC2 - B - 메모리 과부하 ( 80% 초과 )", target = "ec2_b", namespace = "BOAZ/Backend", metric = "mem_used_percent", statistic = "Average", period = 600, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanThreshold", threshold = 80 }
    ec2_a_disk      = { name = "EC2-A-디스크 과부하", description = "EC2 디스크 과부하 ( 80% 초과 )", target = "ec2_a", namespace = "BOAZ/Backend", metric = "disk_used_percent", statistic = "Average", period = 600, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanThreshold", threshold = 80, extra_dimensions = { path = "/", device = "nvme0n1p1", fstype = "ext4" } }
    ec2_b_disk      = { name = "EC2-B-디스크 과부하", description = "EC2 -B - 디스크 과부하 ( 80% 초과 )", target = "ec2_b", namespace = "BOAZ/Backend", metric = "disk_used_percent", statistic = "Average", period = 600, evaluation_periods = 1, datapoints_to_alarm = 1, operator = "GreaterThanThreshold", threshold = 80, extra_dimensions = { path = "/", device = "nvme0n1p1", fstype = "ext4" } }
    rds_cpu         = { name = "boaz-prod-db-High-CPUUtilization", target = "rds", namespace = "AWS/RDS", metric = "CPUUtilization", statistic = "Average", period = 300, evaluation_periods = 1, operator = "GreaterThanThreshold", threshold = 80 }
    rds_connections = { name = "boaz-prod-db-High-DatabaseConnections", target = "rds", namespace = "AWS/RDS", metric = "DatabaseConnections", statistic = "Average", period = 300, evaluation_periods = 1, operator = "GreaterThanThreshold", threshold = 50 }
    # 할당 20GB의 20%(4GiB)
    rds_free_storage = { name = "boaz-prod-db-Low-FreeStorageSpace", description = "RDS 남은 스토리지 4GB 미만 (할당 20GB의 20%)", target = "rds", namespace = "AWS/RDS", metric = "FreeStorageSpace", statistic = "Minimum", period = 300, evaluation_periods = 1, operator = "LessThanThreshold", threshold = 4 * 1024 * 1024 * 1024, treat_missing_data = "notBreaching", ok_actions = true }
    # 현행 80MB. decisions.md "경보 수신 이메일·임계값"의 초기값 50MB와 다름. 조정은 별도 PR
    rds_freeable_memory = { name = "boaz-prod-db-Low-FreeableMemory", description = "RDS 가용 메모리 80MB 미만 지속 (db.t3.micro 메모리 압박)", target = "rds", namespace = "AWS/RDS", metric = "FreeableMemory", statistic = "Average", period = 300, evaluation_periods = 3, datapoints_to_alarm = 3, operator = "LessThanThreshold", threshold = 80 * 1024 * 1024, treat_missing_data = "notBreaching", ok_actions = true }
  }
}

module "obs" {
  source = "../../modules/obs"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix      = "boaz-prod"
  alert_topic_name = local.obs_alert_topic_name

  # 경보 대상 이름(inventory.md 4·5절). compute·database import 뒤 output 참조로 바꿈
  ec2_names              = { ec2_a = "boaz-api-prod-A", ec2_b = "boaz-api-prod-B" }
  db_instance_identifier = local.obs_db_instance_identifier

  # CloudWatch Agent가 쓰는 기존 로그 그룹(2026-05-16 생성). 2026-11-24 30일에서 90일로 변경(OBS-01-03, 사후 원인 조사용)
  app_log_group_name = "/boaz/api/application"
  log_retention_days = 90

  # RDS 로그 그룹(OBS-01-07). error는 import, slowquery는 새로 만듦(2026-11-25 조회 시 없음)
  rds_log_types          = ["error", "slowquery"]
  rds_log_retention_days = 90

  # Discord 경보 전달 Lambda(OBS-01-06). 웹훅 파라미터는 수동 등록한 SecureString
  discord_webhook_parameter_name = "/boaz/obs/discord-webhook-url"
  lambda_log_retention_days      = 30

  # api 헬스체크(OBS-01-08). 사용자와 같은 경로(api CloudFront)로 부름
  health_check_url = "https://api.bigdataboaz.com/actuator/health"

  existing_alarms = local.obs_existing_alarms
  group_vars      = local.group_vars.obs
}
