"""property 테스트 공통 설정 (STA-06, design.md "PBT 적용성 판단").

- 모든 property 테스트는 테스트 1개당 최소 100회 실행한다(design.md: @settings(max_examples=100) 이상).
- 프로필: ci(기본, 100회), thorough(1000회, 로컬 정밀 검사). HYPOTHESIS_PROFILE 환경 변수로 고름.
- CI에서 같은 입력으로 재현되도록 derandomize=True. 실패하면 hypothesis가 최소 반례와 재현 blob을 출력함.
- 테스트는 AWS에 요청하지 않고 순수 fixture만 다룬다.
"""

import os

from hypothesis import HealthCheck, Verbosity, settings

MIN_EXAMPLES = 100

settings.register_profile(
    "ci",
    max_examples=MIN_EXAMPLES,
    deadline=None,
    derandomize=True,
    print_blob=True,
    suppress_health_check=[HealthCheck.too_slow],
)
settings.register_profile(
    "thorough",
    max_examples=MIN_EXAMPLES * 10,
    deadline=None,
    print_blob=True,
    verbosity=Verbosity.normal,
)
settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "ci"))
