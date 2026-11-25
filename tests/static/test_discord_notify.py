"""Discord 경보 전달 Lambda 핸들러 단위 테스트(OBS-01-06). AWS·네트워크 없이 돈다."""

import importlib.util
import json
import pathlib
import re
import urllib.error

import pytest

_PATH = pathlib.Path(__file__).resolve().parents[2] / "modules/obs/lambda/discord_notify/handler.py"
_spec = importlib.util.spec_from_file_location("discord_notify_handler", _PATH)
handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(handler)

URL = "https://discord.invalid/webhook"


def _alarm_event(**overrides):
    alarm = {
        "AlarmName": "EC2-A-CPU 과부하",
        "AlarmArn": "arn:aws:cloudwatch:ap-northeast-2:fake-account:alarm:EC2-A-CPU 과부하",
        "AlarmDescription": "EC2-A 서버 CPU 사용률이 높음",
        "NewStateValue": "ALARM",
        "OldStateValue": "OK",
        "NewStateReason": "Threshold Crossed: 2 datapoints [85.2 (25/11/25 02:55:00), 83.1 (25/11/25 02:50:00)] were greater than or equal to the threshold (80.0).",
        "Region": "Asia Pacific (Seoul)",
        "StateChangeTime": "2026-11-25T03:00:00.000+0000",
        "Trigger": {
            "MetricName": "CPUUtilization",
            "Statistic": "AVERAGE",
            "Period": 300,
            "EvaluationPeriods": 2,
            "DatapointsToAlarm": 2,
            "ComparisonOperator": "GreaterThanOrEqualToThreshold",
            "Threshold": 80.0,
        },
    }
    alarm.update(overrides)
    return {"Records": [{"Sns": {"Subject": "ALARM", "Message": json.dumps(alarm)}}]}


def _format(**overrides):
    return handler.format_message(handler.parse_sns_records(_alarm_event(**overrides))[0])


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


def test_alarm_message_layout():
    text = _format(AlarmDescription="EC2-A 서버 CPU 사용률이 높음\n앱 로그 그룹 확인\n2. WAF 차단 수 확인")
    assert text.splitlines() == [
        "### 🔴 경보 · EC2-A-CPU 과부하",
        "EC2-A 서버 CPU 사용률이 높음",
        "- 현재 값: 85.2%",
        "- 조건: 5분 평균 CPUUtilization ≥ 80%, 2번 연속",
        "- 상태 변화: 정상 → 경보",
        "- 리전: 서울",
        "- 시각: 2026-11-25 12:00 KST",
        "- 먼저 볼 것",
        "    1. 앱 로그 그룹 확인",
        "    2. WAF 차단 수 확인",
        "",
        "[경보 보기](https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#alarmsV2:alarm/EC2-A-CPU%20%EA%B3%BC%EB%B6%80%ED%95%98)",
    ]


def test_ok_message_is_short():
    text = _format(
        NewStateValue="OK",
        OldStateValue="ALARM",
        AlarmDescription="요약\n대처",
        NewStateReason="Threshold Crossed: 1 datapoint [12.4 (25/11/25 03:10:00)] was not greater than or equal to the threshold (80.0).",
    )
    assert text.startswith("### 🟢 복구 · EC2-A-CPU 과부하\n- 현재 값: 12.4%")
    assert "- 상태 변화: 경보 → 정상" in text
    assert "조건" not in text and "먼저 볼 것" not in text and "요약" not in text


@pytest.mark.parametrize("old", ["INSUFFICIENT_DATA", None])
def test_ok_not_from_alarm_is_normal_not_recovery(old):
    # 새 경보 생성·데이터 재개(데이터 부족 → 정상)는 장애 복구가 아님
    text = _format(NewStateValue="OK", OldStateValue=old)
    assert text.startswith("### 🟢 정상 · EC2-A-CPU 과부하")


def test_insufficient_data_label():
    text = _format(NewStateValue="INSUFFICIENT_DATA", NewStateReason="Insufficient Data: 1 datapoint was unknown.")
    assert text.startswith("### ⚪ 데이터 부족 · ")
    assert "- 사유: Insufficient Data: 1 datapoint was unknown." in text


def test_us_east_1_region_and_link():
    text = _format(AlarmArn="arn:aws:cloudwatch:us-east-1:fake-account:alarm:x")
    assert "- 리전: 버지니아 북부(us-east-1)" in text
    assert "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#" in text


def test_missing_optional_fields_still_formats():
    alarm = {"AlarmName": "x", "NewStateValue": "ALARM", "NewStateReason": "사유"}
    text = handler.format_message({"Message": json.dumps(alarm)})
    assert text == "### 🔴 경보 · x\n- 사유: 사유"


@pytest.mark.parametrize(
    ("metric", "threshold", "expected"),
    [
        ("FreeStorageSpace", 4 * 1024**3, "FreeStorageSpace < 4.0GiB"),
        ("FreeableMemory", 80 * 1024**2, "FreeableMemory < 80MiB"),
        ("DatabaseConnections", 50, "DatabaseConnections < 50"),
    ],
)
def test_condition_units(metric, threshold, expected):
    trigger = {"MetricName": metric, "Statistic": "MINIMUM", "Period": 300, "EvaluationPeriods": 3, "DatapointsToAlarm": 2,
               "ComparisonOperator": "LessThanThreshold", "Threshold": threshold}
    assert handler._condition(trigger) == f"5분 최소 {expected}, 3번 중 2번"


def test_markdown_in_names_is_escaped():
    text = _format(AlarmName="a*b_c", AlarmDescription="[링크](x) **굵게**")
    assert r"a\*b\_c" in text
    assert r"\[링크\](x) \*\*굵게\*\*" in text


def test_kst_conversion_falls_back_to_raw():
    assert handler._kst("2026-11-25T15:30:00.000+0000") == "2026-11-26 00:30 KST"
    assert handler._kst("이상한 값") == "이상한 값"


def test_plain_message_uses_subject():
    text = handler.format_message({"Subject": "테스트", "Message": "본문"})
    assert text == "**테스트**\n본문"


@pytest.mark.parametrize(
    "sns",
    [{"Subject": None, "Message": "가" * 5000}, {"Message": json.dumps({"AlarmName": "x", "NewStateValue": "ALARM", "AlarmDescription": "요약\n" + "가" * 5000})}],
)
def test_message_is_truncated_to_discord_limit(sns):
    text = handler.format_message(sns)
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
    assert len(sent) == 2 and all(url == URL + "?wait=true" for _, url in sent)


def test_handler_reads_webhook_every_invocation(monkeypatch):
    # 캐시하지 않아 시즌 중 SSM의 웹훅을 바꾸면 다음 호출부터 바로 반영됨
    urls = iter(["https://discord.invalid/old", "https://discord.invalid/new"])
    sent = []
    monkeypatch.setattr(handler, "_webhook_url", lambda: next(urls))
    monkeypatch.setattr(handler, "send", lambda content, url: sent.append(url))
    handler.lambda_handler(_alarm_event(), None)
    handler.lambda_handler(_alarm_event(), None)
    assert sent == ["https://discord.invalid/old?wait=true", "https://discord.invalid/new?wait=true"]


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        ("https://discord.invalid/api/webhooks/1/t", "https://discord.invalid/api/webhooks/1/t?wait=true"),
        ("https://discord.invalid/w?thread_id=9", "https://discord.invalid/w?thread_id=9&wait=true"),
        ("https://discord.invalid/w?wait=false", "https://discord.invalid/w?wait=true"),
    ],
)
def test_with_wait_keeps_existing_query(url, expected):
    assert handler.with_wait(url) == expected


def test_timeout_budget_fits_lambda_timeout():
    # Lambda timeout(modules/obs/discord.tf) 안에 SSM 조회 최악 + HTTP 2번 + 최대 대기가 들어가야 함
    ssm_worst = handler.SSM_TIMEOUT_SECONDS * 2 * handler.SSM_MAX_ATTEMPTS
    worst = ssm_worst + handler.HTTP_TIMEOUT_SECONDS * handler.MAX_ATTEMPTS + handler.RETRY_AFTER_CAP_SECONDS
    tf = (_PATH.parents[2] / "discord.tf").read_text(encoding="utf-8")
    timeout = int(re.search(r"^\s*timeout\s*=\s*(\d+)", tf, re.M).group(1))
    assert timeout == 30
    # 콜드 스타트(boto3 import 등) 여유로 5초 이상 남김
    assert worst + 5 <= timeout
