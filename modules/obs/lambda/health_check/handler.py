"""api 헬스체크 Lambda (docs/wbs/20-obs.md OBS-01-08, 이슈 #118).

- EventBridge 규칙이 1분마다 비동기로 호출함. Lambda 비동기 재시도는 0회
- 사용자와 같은 경로(api CloudFront 도메인)로 /actuator/health를 부르고, 200이고 status가 UP이면 성공
- 결과를 사용자 지정 지표(성공 1, 실패 0)로 남김. 지표를 남기지 못하면 예외를 내고, 경보는 비어 있는 지표도 실패로 봄
- User-Agent를 반드시 넣음(WAF 관리형 규칙이 User-Agent 없는 요청을 막음)
- 표준 라이브러리만 씀(boto3는 Lambda 런타임에 포함). boto3는 함수 안에서 import해 테스트가 AWS 없이 돌게 함
"""

import json
import os
import urllib.error
import urllib.request

HTTP_TIMEOUT_SECONDS = 5
MAX_BODY_BYTES = 4096
USER_AGENT = "boaz-health-check"


def check(url: str, opener=urllib.request.urlopen) -> tuple[bool, str]:
    """헬스체크 주소를 한 번 부르고 (성공 여부, 사유)를 돌려줌. 네트워크 오류도 실패로 돌려줌(예외를 내지 않음)."""
    request = urllib.request.Request(url, method="GET", headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with opener(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            status = response.status
            body = response.read(MAX_BODY_BYTES)
    except urllib.error.HTTPError as error:
        return False, f"HTTP {error.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return False, f"연결 실패: {type(error).__name__}"

    if status != 200:
        return False, f"HTTP {status}"
    try:
        payload = json.loads(body)
    except ValueError:
        return False, "응답이 JSON이 아님"
    state = payload.get("status") if isinstance(payload, dict) else None
    if state != "UP":
        return False, f"status {state}"
    return True, "UP"


def put_metric(healthy: bool, client=None) -> None:
    if client is None:
        import boto3  # Lambda 런타임에만 있음

        client = boto3.client("cloudwatch")
    client.put_metric_data(
        Namespace=os.environ["METRIC_NAMESPACE"],
        MetricData=[{"MetricName": os.environ["METRIC_NAME"], "Value": 1 if healthy else 0, "Unit": "Count"}],
    )


def lambda_handler(event, context):
    healthy, reason = check(os.environ["HEALTH_CHECK_URL"])
    put_metric(healthy)
    result = {"healthy": healthy, "reason": reason}
    print(json.dumps(result, ensure_ascii=False))
    return result
