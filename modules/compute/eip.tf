# EC2-A Elastic IP와 연결 (CMP-01-02)
#
# - 기존 EIP와 연결을 import함. api CloudFront origin이 이 주소에서 나온 퍼블릭 DNS라 둘 다 삭제를 막음
# - aws_eip에 instance를 적지 않음. 연결은 aws_eip_association 하나만 관리함(이중 관리 방지)

resource "aws_eip" "main" {
  domain = "vpc"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eip_association" "main" {
  allocation_id = aws_eip.main.id
  instance_id   = aws_instance.this["ec2_a"].id

  lifecycle {
    prevent_destroy = true
  }
}
