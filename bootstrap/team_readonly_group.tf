# 팀원 Terraform 작업용 읽기 전용 IAM 그룹 (#44 "팀원 AWS 접근")
#
# 결정(docs/records/decisions.md "팀원 접근 방식 / 권한 범위 / apply 실행 주체"):
# - 접근: IAM 사용자. CLI는 각자 액세스 키로 사용(막지 않음). MFA 강제는 하지 않음
# - 권한: 읽기 전용(ReadOnlyAccess) + state 접근(plan용). 쓰기·apply 없음
# - apply: 인프라 리드(admin_daehyun·admin_seoyeon)만. 팀원은 재조사·plan까지
#
# 그룹·정책만 코드로 관리함. 팀원 IAM 사용자는 이름이 공개 저장소에 들어갈 수 없어 코드 밖(CLI)에서 만들어 이 그룹에 넣음.
# 첫 로그인 시 비밀번호를 바꿀 수 있도록 IAMUserChangePassword를 그룹에 붙임.

resource "aws_iam_group" "terraform_readonly" {
  name = "terraform-readonly"
}

# 모든 AWS 서비스 조회(describe/list/get). import 재조사와 plan에 필요
resource "aws_iam_group_policy_attachment" "terraform_readonly_read_only" {
  group      = aws_iam_group.terraform_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# CI 역할과 같은 state 접근 + 데이터 영역 읽기 거부(ci_plan_role.tf의 공용 정책)
resource "aws_iam_group_policy_attachment" "terraform_readonly_state" {
  group      = aws_iam_group.terraform_readonly.name
  policy_arn = aws_iam_policy.terraform_plan.arn
}

# 첫 로그인 시 본인 콘솔 비밀번호 변경 허용(AWS 관리형)
resource "aws_iam_group_policy_attachment" "terraform_readonly_change_password" {
  group      = aws_iam_group.terraform_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

output "terraform_readonly_group_name" {
  description = "팀원을 넣을 읽기 전용 그룹 이름. 사용자 생성 후 aws iam add-user-to-group으로 추가"
  value       = aws_iam_group.terraform_readonly.name
}
