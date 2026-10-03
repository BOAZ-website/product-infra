# compute 모듈
# 담당 명세서: CMP (docs/wbs/24-cmp.md) · 이슈: #56 CMP-01, #57 CMP-02, #58 CMP-03
# 관리 자원: EC2-A·EC2-B, EIP·연결, `aws_ec2_instance_state`(EC2-B), Target Group·등록, ALB·listener(`season.alb_enabled`일 때만)
#
# - resource·data는 이 폴더에 작성함. 자원이 많으면 역할별 파일로 나눔(예: vpc.tf, security_groups.tf)
# - 작성 규칙: docs/guides/import-procedure.md 1절 "모듈 작성 규칙"
# - 이 파일은 비워 두거나 자원을 직접 적어도 됨
