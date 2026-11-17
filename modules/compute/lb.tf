# Target Group·등록·ALB·listener (CMP-02)
#
# - Target Group과 EC2-A 등록은 import 대상이며 새로 만들지 않음. 교체를 일으키는 속성(이름·포트·프로토콜·VPC·대상 유형)은 실제 값과 같게 둠
# - 등록 대상은 시즌 상태로 정함(off: EC2-A, on: EC2-A·EC2-B, local.season.target_keys)
# - ALB·listener는 시즌 on일 때만 있음(local.season.alb_enabled). 평시에는 없으므로 import하지 않음
# - origin 교체(api_origin = alb)는 이 파일이 아니라 cdn 그룹이 alb_dns_name output으로 함(CMP-02-03, 별도 apply)

resource "aws_lb_target_group" "api" {
  name             = var.target_group.name
  port             = var.target_group.port
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "instance"
  ip_address_type  = "ipv4"
  vpc_id           = var.vpc_id

  deregistration_delay          = 300
  slow_start                    = 0
  load_balancing_algorithm_type = "round_robin"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.target_group.health_check_path
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  # 고정 세션은 꺼져 있음. 실제 값의 유형·유지 시간을 같이 적어 plan 차이를 없앰
  stickiness {
    enabled         = false
    type            = "lb_cookie"
    cookie_duration = 86400
  }

  tags = var.target_group.tags

  lifecycle {
    prevent_destroy = true
  }
}

# 등록 키는 역할 키(ec2_a, ec2_b). 평시에 EC2-A 등록만 import하고, 시즌 on이면 EC2-B 등록이 새로 생김
# EC2-B 등록은 최신 번들 재배포가 끝난 뒤 on apply로만 생겨야 함(CMP-03, 런북 순서)
resource "aws_lb_target_group_attachment" "api" {
  for_each = toset(var.season.target_keys)

  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.this[each.key].id
  port             = var.target_group.port
}

# 시즌 on일 때만 만드는 ALB. 보안 그룹·서브넷은 network output(ALB 보안 그룹, 퍼블릭 서브넷 2a·2c)
resource "aws_lb" "api" {
  count = var.season.alb_enabled ? 1 : 0

  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = values(var.subnet_ids)
}

resource "aws_lb_listener" "http" {
  count = var.season.alb_enabled ? 1 : 0

  load_balancer_arn = aws_lb.api[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
