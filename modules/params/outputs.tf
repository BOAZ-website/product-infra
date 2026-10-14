# params 모듈 출력
# - 모든 output에 description 필수(tflint)
# - 제안 이름: 없음(P7 참조 전환은 Phase 2 2차 뒤 STA-08)
# - 이름을 바꿀 때는 사용하는 그룹 담당과 합의함

output "existing_names" {
  description = "`/boaz/infra` 아래 실제로 있는 파라미터 전체 이름(값 아님). root 개수 검사용"
  value       = data.aws_ssm_parameters_by_path.infra.names
}

output "existing_types" {
  description = "existing_names와 같은 순서의 파라미터 타입(값 아님). root 타입 검사용"
  value       = data.aws_ssm_parameters_by_path.infra.types
}
