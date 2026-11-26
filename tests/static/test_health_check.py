"""api 헬스체크 Lambda 단위 테스트(OBS-01-08). AWS·네트워크 없이 돈다."""

import http.client
import importlib.util
import io
import pathlib
import re
import urllib.error

import pytest

_PATH = pathlib.Path(__file__).resolve().parents[2] / "modules/obs/lambda/health_check/handler.py"
_spec = importlib.util.spec_from_file_location("health_check_handler", _PATH)
handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(handler)

URL = "https://api.example.invalid/actuator/health"


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self, limit):
        return self._body[:limit]

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _opener(result):
    """정해진 응답을 돌려주거나 예외를 던지는 가짜 urlopen. 받은 요청을 기록함."""
    calls = []

    def opener(request, timeout):
        calls.append((request, timeout))
        if isinstance(result, BaseException):
            raise result
        return result

    opener.calls = calls
    return opener


# --- 판정 ---


def test_up_is_healthy():
    assert handler.check(URL, opener=_opener(FakeResponse(200, b'{"status":"UP"}'))) == (True, "UP")


@pytest.mark.parametrize(
    ("body", "reason"),
    [
        (b'{"status":"DOWN"}', "status DOWN"),
        (b'{"status":"OUT_OF_SERVICE"}', "status OUT_OF_SERVICE"),
        (b"{}", "status None"),
        (b"[]", "status None"),
        (b"<html>error</html>", "응답이 JSON이 아님"),
    ],
)
def test_non_up_body_is_unhealthy(body, reason):
    assert handler.check(URL, opener=_opener(FakeResponse(200, body))) == (False, reason)


def test_non_200_success_status_is_unhealthy():
    assert handler.check(URL, opener=_opener(FakeResponse(204, b""))) == (False, "HTTP 204")


@pytest.mark.parametrize("code", [403, 404, 500, 502, 503, 504])
def test_http_error_is_unhealthy(code):
    error = urllib.error.HTTPError(URL, code, "error", {}, io.BytesIO(b""))
    assert handler.check(URL, opener=_opener(error)) == (False, f"HTTP {code}")


@pytest.mark.parametrize(
    "error",
    [
        urllib.error.URLError("down"),
        TimeoutError(),
        ConnectionResetError(),
        http.client.RemoteDisconnected("closed"),
        http.client.BadStatusLine("x"),
    ],
)
def test_connection_error_is_unhealthy_without_raising(error):
    healthy, reason = handler.check(URL, opener=_opener(error))
    assert healthy is False
    assert reason.startswith("연결 실패: ")


def test_request_has_user_agent_and_timeout():
    # WAF 관리형 규칙(NoUserAgent)이 User-Agent 없는 요청을 막음
    opener = _opener(FakeResponse(200, b'{"status":"UP"}'))
    handler.check(URL, opener=opener)
    request, timeout = opener.calls[0]
    assert request.get_header("User-agent") == handler.USER_AGENT
    assert request.get_method() == "GET"
    assert timeout == handler.HTTP_TIMEOUT_SECONDS


# --- 지표 ---


class FakeCloudWatch:
    def __init__(self):
        self.calls = []

    def put_metric_data(self, **kwargs):
        self.calls.append(kwargs)


@pytest.mark.parametrize(("healthy", "value"), [(True, 1), (False, 0)])
def test_put_metric_value(monkeypatch, healthy, value):
    monkeypatch.setenv("METRIC_NAMESPACE", "BOAZ/HealthCheck")
    monkeypatch.setenv("METRIC_NAME", "ApiHealthy")
    client = FakeCloudWatch()
    handler.put_metric(healthy, client=client)
    assert client.calls == [
        {"Namespace": "BOAZ/HealthCheck", "MetricData": [{"MetricName": "ApiHealthy", "Value": value, "Unit": "Count"}]}
    ]


def test_handler_records_unhealthy_without_raising(monkeypatch):
    monkeypatch.setenv("HEALTH_CHECK_URL", URL)
    recorded = []
    monkeypatch.setattr(handler, "check", lambda url: (False, "HTTP 502"))
    monkeypatch.setattr(handler, "put_metric", recorded.append)
    assert handler.lambda_handler({}, None) == {"healthy": False, "reason": "HTTP 502"}
    assert recorded == [False]


def test_metric_failure_raises(monkeypatch):
    # 지표를 남기지 못하면 예외. 경보는 비어 있는 지표도 실패로 봄
    monkeypatch.setenv("HEALTH_CHECK_URL", URL)
    monkeypatch.setattr(handler, "check", lambda url: (True, "UP"))

    def fail(healthy):
        raise RuntimeError("PutMetricData 실패")

    monkeypatch.setattr(handler, "put_metric", fail)
    with pytest.raises(RuntimeError):
        handler.lambda_handler({}, None)


# --- Terraform과 맞추기 ---


def test_names_and_timeout_match_terraform():
    tf = (_PATH.parents[2] / "health_check.tf").read_text(encoding="utf-8")
    assert re.search(r'health_check_namespace\s*=\s*"BOAZ/HealthCheck"', tf)
    assert re.search(r'health_check_metric_name\s*=\s*"ApiHealthy"', tf)
    timeout = int(re.search(r"^\s*timeout\s*=\s*(\d+)", tf, re.M).group(1))
    # HTTP 제한 + 지표 쓰기 여유가 Lambda timeout 안에 들어가고, 1분 주기보다 충분히 짧아야 함
    assert handler.HTTP_TIMEOUT_SECONDS + 3 <= timeout < 60
    assert 'schedule_expression = "rate(1 minute)"' in tf


class BrokenBodyResponse(FakeResponse):
    def read(self, limit):
        raise http.client.IncompleteRead(b"{")


def test_incomplete_body_is_unhealthy_without_raising():
    # 본문을 읽다 끊기면 IncompleteRead(HTTPException, OSError 아님)가 남
    healthy, reason = handler.check(URL, opener=_opener(BrokenBodyResponse(200, b"")))
    assert (healthy, reason) == (False, "연결 실패: IncompleteRead")
