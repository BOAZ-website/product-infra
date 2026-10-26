# network 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 제안 이름: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `security_group_ids`(역할 키 맵: alb, alb_to_ec2, cf_to_ec2, rds, ec2_to_rds, ssh)
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID. 가용 영역 키(a, c) → ID"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID. 가용 영역 키(a, c) → ID"
  value       = { for k, s in aws_subnet.private : k => s.id }
}
