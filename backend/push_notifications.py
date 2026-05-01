import os
from typing import Iterable

from psycopg2.extras import RealDictCursor

from helper_func import db

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except Exception:
    firebase_admin = None
    credentials = None
    messaging = None


_firebase_disabled_reason_printed = False


def _is_firebase_ready() -> bool:
    global _firebase_disabled_reason_printed

    if firebase_admin is None or credentials is None or messaging is None:
        if not _firebase_disabled_reason_printed:
            print("Firebase Admin SDK is not installed. Push notifications are disabled.")
            _firebase_disabled_reason_printed = True
        return False

    service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    if not service_account_path:
        if not _firebase_disabled_reason_printed:
            print("FIREBASE_SERVICE_ACCOUNT_PATH is not configured. Push notifications are disabled.")
            _firebase_disabled_reason_printed = True
        return False

    if not os.path.exists(service_account_path):
        if not _firebase_disabled_reason_printed:
            print("FIREBASE_SERVICE_ACCOUNT_PATH points to non-existing file. Push notifications are disabled.")
            _firebase_disabled_reason_printed = True
        return False

    if not firebase_admin._apps:
        try:
            cred = credentials.Certificate(service_account_path)
            firebase_admin.initialize_app(cred)
        except Exception as exc:
            if not _firebase_disabled_reason_printed:
                print(f"Failed to initialize Firebase Admin SDK: {exc}")
                _firebase_disabled_reason_printed = True
            return False

    return True


def _chunked(items: list[str], chunk_size: int) -> Iterable[list[str]]:
    for i in range(0, len(items), chunk_size):
        yield items[i:i + chunk_size]


def _mark_tokens_inactive(tokens: list[str]):
    if not tokens:
        return
    with db.cursor() as cur:
        cur.execute(
            """
            UPDATE user_push_token
            SET is_active = FALSE
            WHERE token = ANY(%s)
            """,
            (tokens,),
        )
    db.commit()


def get_user_push_tokens(user_ids: list[int]) -> list[str]:
    if not user_ids:
        return []
    with db.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT DISTINCT token
            FROM user_push_token
            WHERE user_id = ANY(%s)
              AND is_active = TRUE
            """,
            (user_ids,),
        )
        rows = cur.fetchall()
    return [row["token"] for row in rows if row.get("token")]


def send_push_to_users(user_ids: list[int], title: str, body: str, data: dict[str, str] | None = None):
    if not user_ids or not _is_firebase_ready():
        return

    tokens = get_user_push_tokens(user_ids)
    if not tokens:
        return

    payload_data = {}
    if data:
        for key, value in data.items():
            payload_data[str(key)] = "" if value is None else str(value)

    invalid_tokens: list[str] = []

    for token_batch in _chunked(tokens, 500):
        try:
            message = messaging.MulticastMessage(
                tokens=token_batch,
                notification=messaging.Notification(title=title, body=body),
                data=payload_data,
            )
            response = messaging.send_each_for_multicast(message)
            for index, send_response in enumerate(response.responses):
                if send_response.success:
                    continue
                exc = send_response.exception
                if exc is None:
                    continue
                error_text = str(exc)
                if "registration-token-not-registered" in error_text or "invalid-argument" in error_text:
                    invalid_tokens.append(token_batch[index])
        except Exception as exc:
            print(f"Failed to send push notification batch: {exc}")

    if invalid_tokens:
        try:
            _mark_tokens_inactive(invalid_tokens)
        except Exception as exc:
            print(f"Failed to mark invalid push tokens inactive: {exc}")
