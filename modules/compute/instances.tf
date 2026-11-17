# EC2-A(상시)·EC2-B(시즌용) 인스턴스와 EC2-B 전원 상태 (CMP-01)
#
# - 두 인스턴스 모두 import 대상이며 새로 만들지 않음. 교체를 일으키는 속성(서브넷·key pair·루트 볼륨 암호화 등)은 실제 값과 같게 둠
# - AMI·user_data는 항상 ignore_changes(CMP-01-03). AMI는 지정이 필수라 이름·소유자 별칭으로 조회해 넘김(ID를 코드에 적지 않음). user_data는 지정하지 않음
# - 기능 태그(app=boaz-api)와 전원 상태는 ignore_changes에 넣지 않음. 바꾸면 plan에 변경이 나와야 함(CMP-01-03)
# - 종료 방지(disable_api_termination)가 꺼져 있으므로 삭제는 prevent_destroy로만 막음(CMP-01-04)

# 인스턴스를 처음 만들 때 쓴 AMI. EC2-A는 Ubuntu 공개 이미지, EC2-B는 이 계정 소유 이미지라 서로 다름
# 공개 이미지는 지원 종료(deprecated) 표시가 붙은 뒤에도 조회되도록 include_deprecated를 켬
data "aws_ami" "this" {
  for_each = var.instances

  owners             = [each.value.ami.owner]
  include_deprecated = true

  filter {
    name   = "name"
    values = [each.value.ami.name]
  }
}

resource "aws_instance" "this" {
  for_each = var.instances

  ami                    = data.aws_ami.this[each.key].id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[each.value.subnet_key]
  vpc_security_group_ids = values(var.security_group_ids)
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name

  # EC2-B 기능 태그는 시즌 상태로 정함(off: 없음, on: app=boaz-api). EC2-A 태그는 root에서 고정값으로 넘김
  tags = merge(
    { Name = each.value.name },
    each.value.tags,
    each.key == "ec2_b" ? var.season.ec2_b_functional_tags : {},
  )

  credit_specification {
    cpu_credits = "unlimited"
  }

  # IMDSv2 필수
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "disabled"
  }

  # 루트 볼륨은 암호화되어 있지 않음. encrypted 값이 다르면 교체됨
  root_block_device {
    volume_type           = var.root_volume.type
    volume_size           = var.root_volume.size
    iops                  = var.root_volume.iops
    throughput            = var.root_volume.throughput
    encrypted             = false
    delete_on_termination = true
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data]
  }
}

# EC2-B 켜기·끄기. off면 stopped, on이면 running(local.season.ec2_b_state)
# ASG를 쓰지 않는 이유: docs/records/decisions.md "EC2-B 제어 방식"
resource "aws_ec2_instance_state" "ec2_b" {
  instance_id = aws_instance.this["ec2_b"].id
  state       = var.season.ec2_b_state
}
