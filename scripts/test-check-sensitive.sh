#!/usr/bin/env bash
#
# check-sensitive.sh 회귀 검사
#   - 잡아야 하는 값(must_fail)은 하나씩 넣어 검사 실패를 확인
#   - 통과해야 하는 값(must_pass)은 하나씩 넣어 검사 성공을 확인
#   샘플 값은 이 파일 자체가 검사에 걸리지 않도록 실행할 때 조립함
#
# 사용법: scripts/test-check-sensitive.sh

set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check-sensitive.sh"
h='0fc2b553b2bbfaee0'

must_fail=(
  "8.8.""8.8" "서버 주소 3.34.""120.7" "ec2-3-34-""120-7.ap-northeast-2.compute.amazonaws.com"
  "AKIA""IOSFODNN7EXAMPLE" "-----BEGIN RSA PRI""VATE KEY-----"
  "계정 1234567""89012" "arn:aws:iam::1234567""89012:role/x"
  "ami""-$h" "vol""-$h" "sgr""-$h" "snap""-$h" "eni""-$h" "nat""-$h"
  "vpce""-$h" "tgw-attach""-$h" "lt""-$h" "i""-$h" "vpc""-$h"
  "pass""word=abcdefghijk"
  "pass""word=CorrectHorseBatteryStaple"
  "pass""word=exampleSecret9"
  "  pass""word = \"CorrectHorseBatteryStaple\""
  "{\"to""ken\": \"abcdefgh12345678\"}"
  "pass""word = \"Correct Horse Battery Staple\""
  "pass""word = 'Correct Horse Battery Staple'"
  "sec""ret=QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
  # IAM 사용자명 규칙(admin_ + 소문자 이름). 실제 이름이 아닌 가짜 값으로 검사
  "관리자(admin""_sample, Admin 그룹)" "admin""_sample·admin""_other"
  # 해시 제외 규칙이 같은 줄의 계정 ID까지 지우면 안 됨
  "--hash=sha256:$(printf 'a%.0s' {1..64}) 계정 1234567""89012"
)
must_pass=(
  "db_pass""word = var.db_password"
  "to""ken: secrets.GH_TOKEN"
  "sec""ret = aws_secretsmanager_secret.app.id"
  "api_""key = \"example\""
  "pass""word = \"xxxxxxxx\""
  "- RDS pass""word: Terraform 값 관리 대상이 아니며"
  "사설 대역 10.0.0.0/16"
  # 앞에 식별자가 붙은 admin_ 이름은 사용자명이 아님(출력 이름 등)
  "frontend_admin""_distribution_id" "관리자(Admin 그룹, 운영진 3명)"
  # sha256 해시 안의 12자리 숫자 구간은 계정 ID가 아님(tests/requirements.txt, .terraform.lock.hcl)
  "    --hash=sha256:ab1234567""89012cd$(printf 'e%.0s' {1..48})"
  "    \"zh:1234567""89012$(printf 'f%.0s' {1..52})\","
)

# $1: 파일 내용, $2: 파일명(생략 시 sample.md)
run_one() {
  local dir name="${2:-sample.md}"
  dir=$(mktemp -d)
  (cd "$dir" && git init -q && printf '%s\n' "$1" > "$name" && git add -- "$name" && bash "$script" >/dev/null)
  local rc=$?
  rm -rf "$dir"
  return $rc
}

failed=0
for v in "${must_fail[@]}"; do
  if run_one "$v"; then echo "  잡혀야 하는데 통과함: $v"; failed=1; fi
done
# 특수 문자(줄바꿈·한글)가 든 파일명도 검사해야 함
special_names=($'bad\nname.md' "한글-문서.md")
for n in "${special_names[@]}"; do
  if run_one "ami""-$h" "$n"; then echo "  잡혀야 하는데 통과함: 특수 문자 파일명 $n"; failed=1; fi
done
for v in "${must_pass[@]}"; do
  if ! run_one "$v"; then echo "  통과해야 하는데 걸림: $v"; failed=1; fi
done

[ "$failed" -eq 0 ] && echo "✅ check-sensitive.sh 회귀 검사 통과 ($(( ${#must_fail[@]} + ${#special_names[@]} ))건 탐지, ${#must_pass[@]}건 통과)"
exit "$failed"
