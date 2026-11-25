"""SNS 경보를 Discord 웹훅으로 보내는 Lambda (docs/wbs/20-obs.md OBS-01-06).

- SNS가 비동기로 호출함. Lambda 비동기 재시도는 0회이고, 이 코드 안에서 한 번만 다시 보냄
- Discord 응답이 2xx가 아니면(429 포함) 예외를 냄. 실패 시 대상(on-failure destination)이 원래 이벤트를 이메일 전용 주제로 넘김
- 형식이 틀린 이벤트(SNS 메시지 구조가 아닌 입력)도 예외를 냄
- 웹훅 URL은 SSM SecureString을 실행 시 읽음. URL을 로그에 남기지 않음
- 표준 라이브러리만 씀(boto3는 Lambda 런타임에 포함). boto3는 함수 안에서 import해 테스트가 AWS 없이 돌게 함
"""

import json
import os
import re
import time
import urllib.parse
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

HTTP_TIMEOUT_SECONDS = 3
RETRY_AFTER_CAP_SECONDS = 5
DEFAULT_RETRY_WAIT_SECONDS = 1
MAX_ATTEMPTS = 2  # 처음 1번 + 다시 보내기 1번
DISCORD_CONTENT_LIMIT = 2000

# 제목 형식. 나중에 바꾸기 쉽게 한 곳에 둠
TITLE_FORMAT = "### {label} · {name}"

STATE_TITLES = {
    "ALARM": "🔴 경보",
    "OK": "🟢 복구",
    "INSUFFICIENT_DATA": "⚪ 데이터 부족",
}
STATE_NAMES = {"ALARM": "경보", "OK": "정상", "INSUFFICIENT_DATA": "데이터 부족"}
REGION_NAMES = {"ap-northeast-2": "서울", "us-east-1": "버지니아 북부(us-east-1)"}
# SNS 경보 메시지의 Statistic은 대문자(AVERAGE)로 옴. 대문자로 맞춰 찾음
STATISTIC_NAMES = {"AVERAGE": "평균", "SUM": "합계", "MINIMUM": "최소", "MAXIMUM": "최대", "SAMPLECOUNT": "개수"}
OPERATORS = {
    "GreaterThanOrEqualToThreshold": "≥",
    "GreaterThanThreshold": ">",
    "LessThanThreshold": "<",
    "LessThanOrEqualToThreshold": "≤",
}
PERCENT_METRICS = {"CPUUtilization", "mem_used_percent", "disk_used_percent", "5xxErrorRate", "4xxErrorRate"}
BYTE_METRICS = {"FreeStorageSpace", "FreeableMemory"}
KST = timezone(timedelta(hours=9))

_webhook_url_cache = None


class DeliveryError(Exception):
    """Discord 전달 실패. 실패 시 대상으로 넘기기 위해 Lambda 밖으로 던짐."""


def _webhook_url() -> str:
    global _webhook_url_cache
    if _webhook_url_cache is None:
        import boto3  # Lambda 런타임에만 있음

        response = boto3.client("ssm").get_parameter(Name=os.environ["WEBHOOK_PARAMETER_NAME"], WithDecryption=True)
        _webhook_url_cache = response["Parameter"]["Value"]
    return _webhook_url_cache


def parse_sns_records(event) -> list[dict]:
    """SNS 이벤트에서 Sns 항목 목록을 꺼냄. 구조가 다르면 ValueError."""
    if not isinstance(event, dict):
        raise ValueError("이벤트가 객체가 아님")
    records = event.get("Records")
    if not isinstance(records, list) or not records:
        raise ValueError("Records가 없거나 비어 있음")
    out = []
    for record in records:
        sns = record.get("Sns") if isinstance(record, dict) else None
        if not isinstance(sns, dict) or not isinstance(sns.get("Message"), str):
            raise ValueError("SNS 메시지 구조가 아님")
        out.append(sns)
    return out


def _escape(text) -> str:
    """경보 이름·설명에 든 Discord 마크다운 기호가 서식으로 해석되지 않게 함."""
    return re.sub(r"([\\*_~`|\[\]])", r"\\\1", str(text))


def _number(value, metric: str) -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if metric in BYTE_METRICS:
        if number >= 1024**3:
            return f"{number / 1024**3:.1f}GiB"
        return f"{number / 1024**2:.0f}MiB"
    text = f"{number:.2f}".rstrip("0").rstrip(".")
    return text + ("%" if metric in PERCENT_METRICS else "")


def _condition(trigger: dict) -> str | None:
    """Trigger를 '5분 평균 CPUUtilization ≥ 80%, 2번 연속' 같은 문장으로 바꿈."""
    metric = trigger.get("MetricName")
    operator = OPERATORS.get(trigger.get("ComparisonOperator"))
    if not metric or not operator or trigger.get("Threshold") is None:
        return None
    parts = []
    period = trigger.get("Period")
    if isinstance(period, (int, float)) and period > 0:
        parts.append(f"{int(period) // 60}분" if period % 60 == 0 else f"{int(period)}초")
    statistic = trigger.get("Statistic") or trigger.get("ExtendedStatistic")
    if statistic:
        parts.append(STATISTIC_NAMES.get(str(statistic).upper(), statistic))
    text = " ".join(parts + [f"{metric} {operator} {_number(trigger['Threshold'], metric)}"])
    evaluations = trigger.get("EvaluationPeriods")
    datapoints = trigger.get("DatapointsToAlarm") or evaluations
    if isinstance(evaluations, int) and evaluations > 1:
        text += f", {evaluations}번 연속" if datapoints == evaluations else f", {evaluations}번 중 {datapoints}번"
    return text


def _current_value(reason: str, metric: str) -> str | None:
    """NewStateReason의 '[85.2 (25/11/25 03:00:00)]'에서 가장 최근 값을 꺼냄."""
    match = re.search(r"\[(-?[0-9][0-9.]*(?:[eE][-+]?[0-9]+)?) \(", reason or "")
    return _number(match.group(1), metric) if match else None


def _region(alarm: dict) -> str | None:
    arn = alarm.get("AlarmArn") or ""
    parts = arn.split(":")
    return parts[3] if len(parts) > 3 and parts[3] else None


def _kst(value) -> str:
    try:
        moment = datetime.strptime(str(value), "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        return str(value)
    return moment.astimezone(KST).strftime("%Y-%m-%d %H:%M KST")


def _truncate(text: str) -> str:
    if len(text) > DISCORD_CONTENT_LIMIT:
        return text[: DISCORD_CONTENT_LIMIT - 3] + "..."
    return text


def _format_alarm(alarm: dict) -> str:
    state = alarm.get("NewStateValue", "")
    trigger = alarm.get("Trigger") if isinstance(alarm.get("Trigger"), dict) else {}
    metric = trigger.get("MetricName", "")
    region = _region(alarm)
    description = [line.strip() for line in str(alarm.get("AlarmDescription") or "").splitlines() if line.strip()]

    lines = [TITLE_FORMAT.format(label=STATE_TITLES.get(state, state), name=_escape(alarm["AlarmName"]))]
    if state != "OK" and description:
        lines.append(_escape(description[0]))

    fields = []
    value = _current_value(alarm.get("NewStateReason", ""), metric)
    if value is not None:
        fields.append(("현재 값", value))
    elif state != "OK" and alarm.get("NewStateReason"):
        fields.append(("사유", _escape(alarm["NewStateReason"])))
    condition = _condition(trigger)
    if state != "OK" and condition:
        fields.append(("조건", condition))
    old = alarm.get("OldStateValue")
    if old:
        fields.append(("상태 변화", f"{STATE_NAMES.get(old, old)} → {STATE_NAMES.get(state, state)}"))
    if region:
        fields.append(("리전", REGION_NAMES.get(region, region)))
    elif alarm.get("Region"):
        fields.append(("리전", _escape(alarm["Region"])))
    if alarm.get("StateChangeTime"):
        fields.append(("시각", _kst(alarm["StateChangeTime"])))
    lines += [f"- **{label}:** {text}" for label, text in fields]

    guide = description[1:]
    if state != "OK" and guide:
        # 대처 항목은 '먼저 볼 것' 아래에 4칸 들여 써서 하위 목록으로 보임
        lines.append("- **먼저 볼 것**")
        for number, line in enumerate(guide, start=1):
            body = re.sub(r"^([-*] |[0-9]+\. )", "", line)
            lines.append(f"    {number}. {_escape(body)}")

    if region:
        name = urllib.parse.quote(alarm["AlarmName"], safe="")
        url = f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#alarmsV2:alarm/{name}"
        lines += ["", f"[경보 보기]({url})"]
    return "\n".join(lines)


def format_message(sns: dict) -> str:
    """CloudWatch 경보 메시지면 항목별로 풀어 쓰고, 아니면 제목과 본문을 그대로 씀."""
    raw = sns["Message"]
    try:
        alarm = json.loads(raw)
    except json.JSONDecodeError:
        alarm = None

    if isinstance(alarm, dict) and "AlarmName" in alarm:
        return _truncate(_format_alarm(alarm))
    subject = sns.get("Subject") or "SNS 알림"
    return _truncate(f"**{_escape(subject)}**\n{_escape(raw)}")


def _post(url: str, content: str) -> tuple[int, float | None]:
    """Discord에 보내고 (상태 코드, Retry-After 초)를 돌려줌. 연결 실패는 예외 그대로."""
    body = json.dumps({"content": content, "allowed_mentions": {"parse": []}}).encode()
    request = urllib.request.Request(url, data=body, method="POST", headers={"Content-Type": "application/json", "User-Agent": "boaz-alert-notifier"})
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.status, None
    except urllib.error.HTTPError as error:
        retry_after = error.headers.get("Retry-After") if error.headers else None
        try:
            wait = float(retry_after) if retry_after is not None else None
        except ValueError:
            wait = None
        return error.code, wait


def send(content: str, url: str, post=_post, sleep=time.sleep) -> None:
    """최대 2번 보냄. 2xx면 끝. 429는 Retry-After만큼 기다리되 5초를 넘으면 바로 실패."""
    last = "알 수 없음"
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            status, retry_after = post(url, content)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            status, retry_after, last = None, None, f"연결 실패: {type(error).__name__}"
        else:
            if 200 <= status < 300:
                return
            last = f"HTTP {status}"

        if attempt == MAX_ATTEMPTS:
            break
        if status == 429:
            wait = retry_after if retry_after is not None else DEFAULT_RETRY_WAIT_SECONDS
            if wait > RETRY_AFTER_CAP_SECONDS:
                raise DeliveryError(f"Discord 요청 제한, 대기 {wait}초가 상한 {RETRY_AFTER_CAP_SECONDS}초를 넘음")
            sleep(wait)
    raise DeliveryError(f"Discord 전달 실패({MAX_ATTEMPTS}번 시도): {last}")


def lambda_handler(event, context):
    records = parse_sns_records(event)
    url = _webhook_url()
    for sns in records:
        send(format_message(sns), url)
    print(json.dumps({"delivered": len(records)}))
    return {"delivered": len(records)}
