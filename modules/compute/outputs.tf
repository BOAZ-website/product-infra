# compute 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 제안 이름: `ec2_a_id`, `ec2_b_id`, `ec2_a_public_dns`, `target_group_arn`, `alb_dns_name`(off일 때 null)
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함

output "ec2_a_id" {
  description = "EC2-A 인스턴스 ID(obs 상태 검사 경보)"
  value       = aws_instance.this["ec2_a"].id
}

output "ec2_b_id" {
  description = "EC2-B 인스턴스 ID(obs 상태 검사 경보)"
  value       = aws_instance.this["ec2_b"].id
}

# EIP에서 나온 퍼블릭 DNS라 공인 IP가 들어 있음. PR CI plan 코멘트가 공개되므로 sensitive로 둠
output "ec2_a_public_dns" {
  description = "EC2-A 퍼블릭 DNS(cdn api origin, CDN-02). EIP 연결 기준"
  value       = aws_instance.this["ec2_a"].public_dns
  sensitive   = true
}

# Target Group ARN은 소비 그룹이 없어 output을 만들지 않음(import-procedure.md 1-1-2절)
output "alb_dns_name" {
  description = "ALB DNS 이름(cdn api origin, 시즌 on). 시즌 off면 null"
  value       = one(aws_lb.api[*].dns_name)
}
