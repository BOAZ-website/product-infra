#!/usr/bin/env bash
#
# 공개 저장소 민감 정보 검사
#   - 모든 파일: 공인 IP 주소, AWS 액세스 키, 개인 키 금지
#   - docs/records/ 밖: AWS 계정 ID, 계정 ID가 들어간 ARN, AWS 자원 ID 금지
#
# 사용법:
#   scripts/check-sensitive.sh            # 추적 중인 전체 파일 검사 (CI)
#   scripts/check-sensitive.sh --staged   # 커밋 대기 파일만 검사 (pre-commit)
#
# 규칙 설명: README.md "보안 정보 공개 금지"

set -uo pipefail

if [ "${1:-}" = "--staged" ]; then
  files=$(git diff --cached --name-only --diff-filter=ACMR)
else
  files=$(git ls-files)
fi

# 검사 제외: 이 스크립트 자체, 바이너리성 파일
files=$(printf '%s\n' "$files" | grep -vE '^(scripts/check-sensitive\.sh)$|\.(png|jpg|jpeg|gif|ico|pdf|zip)$' || true)
[ -z "$files" ] && exit 0

read_file() {
  if [ "${MODE:-}" = "--staged" ]; then git show ":$1" 2>/dev/null; else cat "$1" 2>/dev/null; fi
}
MODE="${1:-}"

fail=0
report() { echo "  $1:$2: $3"; fail=1; }

ipv4='([0-9]{1,3}\.){3}[0-9]{1,3}'
private_ip='^(10\.|127\.|0\.0\.0\.0|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'

while IFS= read -r f; do
  [ -f "$f" ] || [ "$MODE" = "--staged" ] || continue
  content=$(read_file "$f") || continue

  # 1) 공인 IP (사설 대역·0.0.0.0 제외)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    line=${hit%%:*}; ip=${hit#*:}
    if ! printf '%s' "$ip" | grep -qE "$private_ip"; then
      report "$f" "$line" "공인 IP 주소: $ip"
    fi
  done < <(printf '%s\n' "$content" | grep -noE "\b$ipv4\b" || true)
  printf '%s\n' "$content" | grep -noE 'ec2-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}\.' \
    | while IFS=: read -r line dns; do echo "  $f:$line: 공인 IP가 들어간 EC2 DNS: $dns"; done | grep . && fail=1

  # 2) AWS 액세스 키, 개인 키
  printf '%s\n' "$content" | grep -nE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}' | while IFS=: read -r line _; do echo "  $f:$line: AWS 액세스 키 형식"; done | grep . && fail=1
  printf '%s\n' "$content" | grep -nE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' | while IFS=: read -r line _; do echo "  $f:$line: 개인 키"; done | grep . && fail=1

  # 3) docs/records/ 밖: 계정 ID·ARN·자원 ID
  case "$f" in docs/records/*) continue ;; esac
  printf '%s\n' "$content" | grep -nE 'arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:|\baccount[^0-9]{0,20}[0-9]{12}\b|계정[^0-9]{0,20}[0-9]{12}\b' \
    | while IFS=: read -r line _; do echo "  $f:$line: AWS 계정 ID 또는 계정 ID가 들어간 ARN"; done | grep . && fail=1
  printf '%s\n' "$content" | grep -noE '\b(vpc|subnet|sg|igw|rtb|acl|eipalloc|eipassoc|pl|i)-[0-9a-f]{8,17}\b' \
    | while IFS=: read -r line id; do echo "  $f:$line: AWS 자원 ID: $id"; done | grep . && fail=1
  # CloudFront 배포 ID(E…), Route53 호스팅 영역 ID(Z…): 대문자·숫자 혼합만
  printf '%s\n' "$content" | grep -noE '\b(E[0-9A-Z]{11,13}|Z0[0-9A-Z]{10,20})\b' | grep -E ':[A-Z]*[0-9]' \
    | while IFS=: read -r line id; do echo "  $f:$line: CloudFront·Route53 ID: $id"; done | grep . && fail=1
done <<< "$files"

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "❌ 공개하면 안 되는 정보가 있습니다. (규칙: README.md '보안 정보 공개 금지')"
  echo "   - 공인 IP·액세스 키·개인 키는 어디에도 적지 않습니다."
  echo "   - 계정 ID·자원 ID는 docs/records/ 에만 적고, 다른 곳에는 역할명(EC2-A, api CloudFront 등)으로 씁니다."
  exit 1
fi
exit 0
