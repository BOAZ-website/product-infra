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
)
must_pass=(
  "db_pass""word = var.db_password"
  "to""ken: secrets.GH_TOKEN"
  "sec""ret = aws_secretsmanager_secret.app.id"
  "api_""key = \"example\""
  "pass""word = \"xxxxxxxx\""
  "- RDS pass""word: Terraform 값 관리 대상이 아니며"
  "사설 대역 10.0.0.0/16"
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
