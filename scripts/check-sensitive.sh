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

[ -z "$files" ] && exit 0

read_file() {
  if [ "${MODE:-}" = "--staged" ]; then git show ":$1" 2>/dev/null; else cat "$1" 2>/dev/null; fi
}
MODE="${1:-}"

fail=0
report() { echo "  $1:$2: $3"; fail=1; }

ipv4='([0-9]{1,3}\.){3}[0-9]{1,3}'
placeholder='^((var|local|env|secrets|data|module)\..+|aws_[a-z0-9_]+\..+|x{3,}|\*{3,}|example|examples|placeholder|sensitive|changeme|dummy|redacted)$'
private_ip='^(10\.|127\.|0\.0\.0\.0|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'

while IFS= read -r f; do
  [ -f "$f" ] || [ "$MODE" = "--staged" ] || continue

  # 내용을 검사할 수 없는 바이너리(이미지·PDF·압축·오피스 문서)는 올리지 않는다
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.webp|*.pdf|*.zip|*.tar|*.gz|*.7z|*.docx|*.xlsx|*.pptx)
      report "$f" 0 "내용을 검사할 수 없는 바이너리 파일. 이 저장소에는 올리지 않는다(필요하면 노션에 첨부)"
      continue ;;
  esac
  if ! content=$(read_file "$f"); then
    report "$f" 0 "파일을 읽을 수 없어 검사하지 못함(권한·인코딩 확인 필요)"
    continue
  fi

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

  # 일반 자격 증명: 키=값 형태의 비밀번호·토큰·시크릿
  #   값 전체가 변수 참조·자리표시자일 때만 제외: var.·local.·env.·secrets.·aws_* 참조, example, xxx, *** 등
  #   ${...}, <...> 형태는 값 문자 범위에 들지 않아 처음부터 잡히지 않는다
  #   값이 줄 끝·따옴표·쉼표·}·주석으로 끝날 때만 잡는다(값 뒤로 문장이 이어지는 설명문 오탐 방지)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    line=${hit%%:*}
    value=$(printf '%s' "${hit#*:}" | sed -E "s/^[^:=]*[:=][[:space:]]*[\"']?//; s/([\"',;}]|[[:space:]]*(#|\/\/)|[[:space:]]*)$//")
    printf '%s' "$value" | grep -qiE "$placeholder" && continue
    report "$f" "$line" "비밀번호·토큰·시크릿 값으로 보이는 키=값"
  done < <(printf '%s\n' "$content" \
    | grep -noiE "(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret|private[_-]?key)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9+/_.@!#%^&*-]{8,}([\"',;}]|[[:space:]]*(#|//)|[[:space:]]*$)" || true)
  # 서비스 토큰 형식: GitHub, Slack, OpenAI 형식, Context7
  printf '%s\n' "$content" \
    | grep -nE '\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b|\bxox[abprs]-[A-Za-z0-9-]{10,}\b|\bsk-[A-Za-z0-9]{20,}\b|\bctx7sk-[A-Za-z0-9-]{20,}\b' \
    | while IFS=: read -r line _; do echo "  $f:$line: 서비스 토큰 형식"; done | grep . && fail=1

  # 3) docs/records/ 밖: 계정 ID·ARN·자원 ID
  case "$f" in docs/records/*) continue ;; esac
  printf '%s\n' "$content" | grep -nE 'arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:|(^|[^0-9])[0-9]{12}([^0-9]|$)' \
    | while IFS=: read -r line _; do echo "  $f:$line: AWS 계정 ID(12자리 숫자) 또는 계정 ID가 들어간 ARN"; done | grep . && fail=1
  printf '%s\n' "$content" | grep -noE '\b(vpc|subnet|sg|sgr|igw|eigw|rtb|rtbassoc|acl|aclassoc|eipalloc|eipassoc|pl|i|ami|vol|snap|eni|nat|vpce|tgw|tgw-attach|pcx|dopt|lt|cgw|vgw|vpn)-[0-9a-f]{8,17}\b' \
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
