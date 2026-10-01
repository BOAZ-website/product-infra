"""property 테스트 실행 환경 자체 검사 (STA-06-01).

설계 Property(P1~P10) 테스트는 tests/property/test_design_invariants.py에 둔다(STA-07부터).
여기서는 환경이 요구 조건(테스트 1개당 100회 이상)을 지키는지만 확인한다.
"""

from hypothesis import given, settings
from hypothesis import strategies as st

from tests.property.conftest import MIN_EXAMPLES

_calls = []


def test_active_profile_runs_at_least_min_examples():
    assert settings().max_examples >= MIN_EXAMPLES


@given(st.integers())
def _count_examples(value):
    _calls.append(value)


def test_given_runs_at_least_min_examples():
    _calls.clear()
    _count_examples()
    assert len(_calls) >= MIN_EXAMPLES
