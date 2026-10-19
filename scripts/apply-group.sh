#!/usr/bin/env bash
# 관리자 로컬 apply 절차(docs/guides/import-procedure.md 2절 3~6단계)를 한 명령으로 실행한다.
#
#   scripts/apply-group.sh <그룹> [이슈 번호]
#   예: AWS_PROFILE=boaz scripts/apply-group.sh iam 51
#
# 순서: dev 최신 확인 → plan -out → 로컬 게이트(plan_gate.py) → 요약 출력 → 확인 입력
#       → 같은 plan 파일로 apply → 다시 plan해 "No changes" 확인 → (이슈 번호가 있으면) 요약을 이슈 코멘트로 남김
# 대상은 -target=module.<그룹>으로 그 그룹만 잡는다. plan에 다른 그룹 주소가 있으면 멈춘다.
# plan 파일·JSON에는 값이 평문으로 들어가므로 저장소 밖 임시 폴더에 두고 끝나면 지운다.
set -euo pipefail

GROUPS_ALLOWED="obs network iam params storage compute database cdn deploy"
group="${1:-}"
issue="${2:-}"
if [[ -z "${group}" || " ${GROUPS_ALLOWED} " != *" ${group} "* ]]; then
  echo "사용법: $0 <${GROUPS_ALLOWED// /|}> [이슈 번호]" >&2
  exit 2
fi
if [[ -n "${issue}" && ! "${issue}" =~ ^[0-9]+$ ]]; then
  echo "이슈 번호는 숫자여야 함: ${issue}" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
cd "${root}"
tf=(terraform -chdir=envs/prod)
target="-target=module.${group}"

# 1. dev 최신 커밋에서만 실행(2절: 머지 뒤 dev에서 apply)
git fetch -q origin dev
[[ "$(git branch --show-current)" == "dev" ]] || { echo "dev 브랜치에서 실행해야 함" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "작업 트리에 변경이 있음. 정리 뒤 실행" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/dev)" ]] || { echo "origin/dev와 다름. git pull --ff-only 뒤 실행" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

"${tf[@]}" init -input=false -lockfile=readonly -backend-config=backend.hcl >/dev/null
"${tf[@]}" validate >/dev/null

# 2. plan 파일 생성
"${tf[@]}" plan -input=false -lock-timeout=5m "${target}" -out="${work}/plan.bin" >/dev/null
"${tf[@]}" show -json "${work}/plan.bin" > "${work}/plan.json"

# 3. 로컬 게이트(위반 시 exit 1)
python3 scripts/plan_gate.py "${work}/plan.json"

# 4. 다른 그룹 자원이 섞였으면 중단(2절: 그 그룹의 import와 승인된 변경만)
others="$(python3 - "${work}/plan.json" "module.${group}." <<'EOF'
import json, sys
plan = json.load(open(sys.argv[1]))
prefix = sys.argv[2]
for rc in plan.get("resource_changes", []):
    if rc["change"]["actions"] != ["no-op"] or rc["change"].get("importing"):
        if not rc["address"].startswith(prefix):
            print(rc["address"])
EOF
)"
if [[ -n "${others}" ]]; then
  echo "다른 그룹 자원이 plan에 있음. dev 최신 상태부터 다시 확인:" >&2
  echo "${others}" >&2
  exit 1
fi

python3 scripts/plan_summary.py summary "${work}/plan.json" > "${work}/summary.md"
cat "${work}/summary.md"

# 5. 사람 확인 뒤 같은 plan 파일로 apply
read -r -p "위 요약대로 ${group} 그룹을 apply하려면 yes 입력: " answer
[[ "${answer}" == "yes" ]] || { echo "중단함"; exit 1; }
"${tf[@]}" apply -input=false "${work}/plan.bin"

# 6. 같은 커밋에서 다시 plan해 "No changes" 확인(-detailed-exitcode: 0 = 변경 없음, 2 = 변경 있음)
set +e
"${tf[@]}" plan -input=false -lock-timeout=5m "${target}" -detailed-exitcode >/dev/null
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "apply 뒤 plan이 No changes가 아님(exit ${rc}). import-log에 기록하고 원인 확인" >&2
  exit 1
fi
echo "apply 완료, 다시 plan 결과 No changes"

# 7. 결과를 그룹 이슈에 남김(요약은 주소·action만 있어 공개 가능, PR CI 코멘트와 같은 형식)
if [[ -n "${issue}" ]]; then
  {
    echo "$(date +%F) ${group} 그룹 apply 완료(\`dev\` $(git rev-parse --short HEAD)). 다시 plan 결과 No changes."
    echo
    cat "${work}/summary.md"
  } > "${work}/comment.md"
  gh issue comment "${issue}" -F "${work}/comment.md"
fi
