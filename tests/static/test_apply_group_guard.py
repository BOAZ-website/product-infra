"""scripts/apply-group.sh 동결 그룹 가드 검사.

동결 그룹(compute·database·cdn)은 ALLOW_FROZEN_GROUP=1 없이는 git·terraform을 호출하기 전에 exit 3으로 멈춰야 한다.
다른 그룹은 가드를 지나가야 하므로, 가드 뒤 첫 단계(git)가 실패하도록 저장소 밖 빈 폴더에서 실행해 exit 3이 아님을 확인한다.
"""

import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "apply-group.sh"


def run(group, tmp_path, allow=None):
    env = {k: v for k, v in os.environ.items() if k != "ALLOW_FROZEN_GROUP"}
    if allow is not None:
        env["ALLOW_FROZEN_GROUP"] = allow
    # 저장소 밖에서 실행해 가드를 지나가면 git rev-parse에서 바로 실패하게 함(AWS·terraform 호출 없음)
    return subprocess.run(["bash", str(SCRIPT), group], cwd=tmp_path, env=env, capture_output=True, text=True)


@pytest.mark.parametrize("group", ["compute", "database", "cdn"])
def test_frozen_group_is_blocked(group, tmp_path):
    r = run(group, tmp_path)
    assert r.returncode == 3
    assert "동결 그룹" in r.stderr


@pytest.mark.parametrize("allow", ["0", "", "yes"])
def test_frozen_group_needs_exact_override(allow, tmp_path):
    assert run("compute", tmp_path, allow).returncode == 3


@pytest.mark.parametrize("group", ["compute", "database", "cdn"])
def test_frozen_group_passes_guard_with_override(group, tmp_path):
    assert run(group, tmp_path, "1").returncode not in (2, 3)


@pytest.mark.parametrize("group", ["obs", "network", "iam", "params", "storage", "deploy"])
def test_other_groups_pass_guard(group, tmp_path):
    assert run(group, tmp_path).returncode not in (2, 3)
