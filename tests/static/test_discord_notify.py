"""Discord 경보 전달 Lambda 핸들러 단위 테스트(OBS-01-06). AWS·네트워크 없이 돈다."""

import importlib.util
import json
import pathlib
import urllib.error

import pytest

_PATH = pathlib.Path(__file__).resolve().parents[2] / "modules/obs/lambda/discord_notify/handler.py"
_spec = importlib.util.spec_from_file_location("discord_notify_handler", _PATH)
handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(handler)

URL = "https://discord.invalid/webhook"


def _alarm_event(**overrides):
    alarm = {
        "AlarmName": "boaz-prod-db-High-CPUUtilization",
        "NewStateValue": "ALARM",
        "NewStateReason": "Threshold Crossed",
        "Region": "Asia Pacific (Seoul)",
        "StateChangeTime": "2026-11-25T03:00:00.000+0000",
    }
    alarm.update(overrides)
    return {"Records": [{"Sns": {"Subject": "ALARM", "Message": json.dumps(alarm)}}]}


class FakePost:
    """응답을 차례로 돌려주는 가짜 전송 함수. 값이 예외면 던짐."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls = 0

    def __call__(self, url, content):
        self.calls += 1
        value = self.responses.pop(0)
        if isinstance(value, BaseException):
            raise value
        return value


# --- 이벤트 형식 ---


@pytest.mark.parametrize(
    "event",
    [None, "text", {}, {"Records": []}, {"Records": [{}]}, {"Records": [{"Sns": {"Message": 1}}]}, {"foo": "bar"}],
)
def test_malformed_event_raises(event):
    with pytest.raises(ValueError):
        handler.parse_sns_records(event)


def test_malformed_event_fails_before_reading_webhook(monkeypatch):
    def fail():
        raise AssertionError("웹훅을 읽으면 안 됨")

    monkeypatch.setattr(handler, "_webhook_url", fail)
    with pytest.raises(ValueError):
        handler.lambda_handler({"foo": "bar"}, None)


# --- 메시지 ---


def test_alarm_message_summary():
    sns = handler.parse_sns_records(_alarm_event(AlarmDescription="RDS CPU 80% 초과"))[0]
    text = handler.format_message(sns)
    assert "🔴 경보" in text
    assert "boaz-prod-db-High-CPUUtilization" in text
    assert "RDS CPU 80% 초과" in text
    assert "Threshold Crossed" in text


def test_plain_message_uses_subject():
    text = handler.format_message({"Subject": "테스트", "Message": "본문"})
    assert text == "**테스트**\n본문"


def test_message_is_truncated_to_discord_limit():
    text = handler.format_message({"Subject": None, "Message": "가" * 5000})
    assert len(text) == handler.DISCORD_CONTENT_LIMIT
    assert text.endswith("...")


# --- 전송·재시도 ---


@pytest.mark.parametrize("status", [200, 204])
def test_2xx_succeeds_without_retry(status):
    post = FakePost((status, None))
    handler.send("x", URL, post=post, sleep=lambda s: None)
    assert post.calls == 1


@pytest.mark.parametrize("status", [400, 401, 404, 500, 503])
def test_non_2xx_retries_once_then_raises(status):
    post = FakePost((status, None), (status, None))
    with pytest.raises(handler.DeliveryError):
        handler.send("x", URL, post=post, sleep=lambda s: None)
    assert post.calls == 2


def test_retry_success_after_failure():
    post = FakePost((500, None), (204, None))
    handler.send("x", URL, post=post, sleep=lambda s: None)
    assert post.calls == 2


def test_429_waits_retry_after_then_retries():
    waits = []
    post = FakePost((429, 2.5), (204, None))
    handler.send("x", URL, post=post, sleep=waits.append)
    assert waits == [2.5]


def test_429_without_header_waits_default():
    waits = []
    post = FakePost((429, None), (204, None))
    handler.send("x", URL, post=post, sleep=waits.append)
    assert waits == [handler.DEFAULT_RETRY_WAIT_SECONDS]


def test_429_over_cap_raises_immediately():
    waits = []
    post = FakePost((429, handler.RETRY_AFTER_CAP_SECONDS + 0.1))
    with pytest.raises(handler.DeliveryError):
        handler.send("x", URL, post=post, sleep=waits.append)
    assert post.calls == 1
    assert waits == []


def test_429_twice_raises():
    post = FakePost((429, 1.0), (429, 1.0))
    with pytest.raises(handler.DeliveryError):
        handler.send("x", URL, post=post, sleep=lambda s: None)


def test_connection_error_retries_then_raises():
    post = FakePost(urllib.error.URLError("down"), TimeoutError())
    with pytest.raises(handler.DeliveryError):
        handler.send("x", URL, post=post, sleep=lambda s: None)
    assert post.calls == 2


def test_error_message_does_not_contain_webhook_url():
    post = FakePost((500, None), (500, None))
    with pytest.raises(handler.DeliveryError) as info:
        handler.send("x", URL, post=post, sleep=lambda s: None)
    assert URL not in str(info.value)


def test_handler_sends_each_record(monkeypatch):
    sent = []
    monkeypatch.setattr(handler, "_webhook_url", lambda: URL)
    monkeypatch.setattr(handler, "send", lambda content, url: sent.append((content, url)))
    event = _alarm_event()
    event["Records"].append({"Sns": {"Subject": "두 번째", "Message": "본문"}})
    assert handler.lambda_handler(event, None) == {"delivered": 2}
    assert len(sent) == 2 and all(url == URL for _, url in sent)


def test_timeout_budget_fits_lambda_timeout():
    # Lambda timeout 15초(modules/obs/discord.tf) 안에 HTTP 2번 + 최대 대기가 들어가야 함
    worst = handler.HTTP_TIMEOUT_SECONDS * handler.MAX_ATTEMPTS + handler.RETRY_AFTER_CAP_SECONDS
    tf = (_PATH.parents[2] / "discord.tf").read_text(encoding="utf-8")
    assert "timeout          = 15" in tf
    assert worst < 15
