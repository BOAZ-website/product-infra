"""SNS 경보를 Discord 웹훅으로 보내는 Lambda (docs/wbs/20-obs.md OBS-01-06).

- SNS가 비동기로 호출함. Lambda 비동기 재시도는 0회이고, 이 코드 안에서 한 번만 다시 보냄
- Discord 응답이 2xx가 아니면(429 포함) 예외를 냄. 실패 시 대상(on-failure destination)이 원래 이벤트를 이메일 전용 주제로 넘김
- 형식이 틀린 이벤트(SNS 메시지 구조가 아닌 입력)도 예외를 냄
- 웹훅 URL은 SSM SecureString을 실행 시 읽음. URL을 로그에 남기지 않음
- 표준 라이브러리만 씀(boto3는 Lambda 런타임에 포함). boto3는 함수 안에서 import해 테스트가 AWS 없이 돌게 함
"""

import json
import os
import time
import urllib.error
import urllib.request

HTTP_TIMEOUT_SECONDS = 3
RETRY_AFTER_CAP_SECONDS = 5
DEFAULT_RETRY_WAIT_SECONDS = 1
MAX_ATTEMPTS = 2  # 처음 1번 + 다시 보내기 1번
DISCORD_CONTENT_LIMIT = 2000

STATE_LABELS = {
    "ALARM": "🔴 경보",
    "OK": "🟢 정상 복구",
    "INSUFFICIENT_DATA": "⚪ 데이터 부족",
}

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


def format_message(sns: dict) -> str:
    """CloudWatch 경보 메시지면 요약하고, 아니면 제목과 본문을 그대로 씀."""
    raw = sns["Message"]
    try:
        alarm = json.loads(raw)
    except json.JSONDecodeError:
        alarm = None

    if isinstance(alarm, dict) and "AlarmName" in alarm:
        state = alarm.get("NewStateValue", "")
        lines = [
            f"**{STATE_LABELS.get(state, state)}** `{alarm['AlarmName']}`",
            str(alarm.get("NewStateReason", "")),
            f"리전: {alarm.get('Region', '-')} · 시각: {alarm.get('StateChangeTime', '-')}",
        ]
        if alarm.get("AlarmDescription"):
            lines.insert(1, str(alarm["AlarmDescription"]))
        text = "\n".join(lines)
    else:
        subject = sns.get("Subject") or "SNS 알림"
        text = f"**{subject}**\n{raw}"

    if len(text) > DISCORD_CONTENT_LIMIT:
        text = text[: DISCORD_CONTENT_LIMIT - 3] + "..."
    return text


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
