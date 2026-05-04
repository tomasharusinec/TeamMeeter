import json
import logging
import os
from typing import Iterable, Optional

from psycopg2.extras import RealDictCursor

from helper_func import db

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except Exception:
    firebase_admin = None
    credentials = None
    messaging = None

logger = logging.getLogger(__name__)

_firebase_disabled_reason_printed = False
_firebase_ready_announced = False
_no_fcm_tokens_warning_emitted = False


# Function below was generated using AI (Gemini)
# Returns default filesystem paths where a Firebase service account JSON may live.
def _service_account_candidates() -> list[str]:
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    return [
        os.path.join(backend_dir, "firebase_service.json"),
        os.path.join(backend_dir, "firebase-service-account.json"),
    ]


# Function below was generated using AI (Gemini)
# Resolves service account path from env or known filenames next to this module.
def resolve_firebase_service_account_path() -> Optional[str]:
    env = (os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH") or "").strip()
    if env and os.path.isfile(env):
        return env
    for path in _service_account_candidates():
        if os.path.isfile(path):
            return path
    return None


# Function below was generated using AI (Gemini)
# Lazily initializes Firebase Admin SDK and prints one-time status if misconfigured.
def _is_firebase_ready() -> bool:
    global _firebase_disabled_reason_printed, _firebase_ready_announced

    if firebase_admin is None or credentials is None or messaging is None:
        if not _firebase_disabled_reason_printed:
            print("Firebase Admin SDK is not installed. Push notifications are disabled.")
            _firebase_disabled_reason_printed = True
        return False

    service_account_path = resolve_firebase_service_account_path()
    if not service_account_path:
        if not _firebase_disabled_reason_printed:
            print(
                "Firebase service account not found. Set FIREBASE_SERVICE_ACCOUNT_PATH "
                "or place firebase_service.json next to push_notifications.py. Push disabled."
            )
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

    if not _firebase_ready_announced:
        print(f"Firebase push notifications enabled ({service_account_path})")
        _firebase_ready_announced = True

    return True


# Function below was generated using AI (Gemini)
# Prints FCM configuration summary once when the Flask app imports the module.
def log_firebase_status_at_startup() -> None:
    print("--- FCM (push) ---")
    path = resolve_firebase_service_account_path()
    if path:
        print(f"Service account JSON: {path}")
    else:
        print(
            "Service account JSON: NOT FOUND — set FIREBASE_SERVICE_ACCOUNT_PATH "
            "or ulož súbor ako backend/firebase_service.json"
        )
    if not _is_firebase_ready():
        print("Výsledok: push zo servera je VYPNUTÝ, kým neopravíš chyby vyššie.")
    print("--- end FCM ---")


# Function below was generated using AI (Gemini)
# Yields fixed-size slices of a token list for FCM multicast batching.
def _chunked(items: list[str], chunk_size: int) -> Iterable[list[str]]:
    for i in range(0, len(items), chunk_size):
        yield items[i:i + chunk_size]


# Function below was generated using AI (Gemini)
# Truncates notification title/body strings to FCM-safe lengths with ellipsis.
def _truncate_fcm_text(value: str, max_len: int) -> str:
    s = "" if value is None else str(value)
    if len(s) <= max_len:
        return s
    return s[: max_len - 1] + "…"


# Function below was generated using AI (Gemini)
# Truncates individual FCM data map values to stay under platform payload limits.
def _truncate_fcm_data_value(value: str, max_len: int = 900) -> str:
    """FCM data payload má limit ~4 KiB celkom; jednotlivé hodnoty drž krátke."""
    s = "" if value is None else str(value)
    if len(s) <= max_len:
        return s
    return s[: max_len - 1] + "…"


# Function below was generated using AI (Gemini)
# Detects FCM errors that mean the device token should be marked inactive in DB.
def _should_mark_fcm_token_inactive(exc: BaseException) -> bool:
    text = str(exc).lower().replace("_", "-")
    if "registration-token-not-registered" in text:
        return True
    if "requested entity was not found" in text:
        return True
    if "not a valid fcm registration token" in text:
        return True
    if "invalid-registration-token" in text:
        return True
    if "invalid-argument" in text and "token" in text:
        return True
    return False


# Function below was generated using AI (Gemini)
# Shrinks FCM data payload iteratively so JSON UTF-8 size stays under max_bytes.
def _cap_fcm_data_map(data: dict[str, str], max_bytes: int = 3800) -> dict[str, str]:
    if not data:
        return {}
    out: dict[str, str] = {str(k): "" if v is None else str(v) for k, v in data.items()}

    def nbytes() -> int:
        return len(json.dumps(out, ensure_ascii=False).encode("utf-8"))

    trim_first = ("push_body", "conversation_name", "push_title", "sender_username")
    while nbytes() > max_bytes:
        progressed = False
        for key in trim_first:
            val = out.get(key) or ""
            if len(val) <= 20:
                continue
            out[key] = val[: max(20, len(val) - 120)] + "…"
            progressed = True
            break
        if not progressed:
            lk = max(out.keys(), key=lambda k: len((out.get(k) or "").encode("utf-8")))
            v = out.get(lk) or ""
            if len(v) <= 12:
                break
            out[lk] = v[:12] + "…"
    return out


# Function below was generated using AI (Gemini)
# Bulk-updates user_push_token rows to is_active=FALSE for invalid FCM tokens.
def _mark_tokens_inactive(tokens: list[str]):
    if not tokens:
        return
    with db.cursor() as cur:
        cur.execute(
            """
            UPDATE user_push_token
            SET is_active = FALSE
            WHERE token IN %s
            """,
            (tuple(tokens),),
        )
    db.commit()


# Function below was generated using AI (Gemini)
# Loads distinct active FCM registration tokens for the given user id list.
def get_user_push_tokens(user_ids: list[int]) -> list[str]:
    if not user_ids:
        return []
    ids = tuple({int(u) for u in user_ids if u is not None})
    if not ids:
        return []
    with db.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT DISTINCT token
            FROM user_push_token
            WHERE user_id IN %s
              AND is_active = TRUE
            """,
            (ids,),
        )
        rows = cur.fetchall()
    return [row["token"] for row in rows if row.get("token")]


# Function below was generated using AI (Gemini)
# Builds Android notification tag string so related pushes collapse in the status bar.
def _android_tag_from_data(data: dict[str, str]) -> Optional[str]:
    if not data:
        return None
    notif_type = (data.get("notification_type") or "").strip()
    if notif_type == "1":
        conv_id = (data.get("conversation_id") or "").strip()
        if conv_id:
            return f"chat-{conv_id}"
    if notif_type in {"2", "4", "5", "6"}:
        activity_id = (data.get("activity_id") or "").strip()
        if activity_id:
            return f"activity-{activity_id}"
    if notif_type == "3":
        target_type = (data.get("target_type") or "").strip()
        target_id = (data.get("target_id") or "").strip()
        if target_type and target_id:
            return f"invite-{target_type}-{target_id}"
    return None


# Function below was generated using AI (Gemini)
# Sends FCM multicast notifications to users, trimming payload and deactivating bad tokens.
def send_push_to_users(
    user_ids: list[int],
    title: str,
    body: str,
    data: Optional[dict[str, str]] = None,
    *,
    data_message_only: bool = False,
):
    global _no_fcm_tokens_warning_emitted
    if not user_ids:
        return
    if not _is_firebase_ready():
        return

    tokens = get_user_push_tokens(user_ids)
    if not tokens:
        if not _no_fcm_tokens_warning_emitted:
            msg = (
                "FCM: žiadne aktívne tokeny v user_push_token — aplikácia musí po prihlásení "
                "zavolať POST /notifications/push-token (Android/iOS s Google Play). "
                "(Ďalšie rovnaké varovania sa už nevypisujú.)"
            )
            print(msg)
            _no_fcm_tokens_warning_emitted = True
        return

    title = _truncate_fcm_text(title, 250)
    body = _truncate_fcm_text(body, 1800)

    payload_data: dict[str, str] = {}
    if data:
        for key, value in data.items():
            payload_data[str(key)] = _truncate_fcm_data_value(
                "" if value is None else str(value),
            )

    if data_message_only:
        # Pre Flutter: v popredí / `onBackgroundMessage` čítame title/body z dát.
        payload_data["push_title"] = _truncate_fcm_text(title, 250)
        payload_data["push_body"] = _truncate_fcm_text(body, 1800)

    payload_data = _cap_fcm_data_map(payload_data, max_bytes=3800)
    android_tag = _android_tag_from_data(payload_data)

    logger.info(
        "FCM dispatch: %s tokens, type=%s tag=%s data_keys=%s",
        len(tokens),
        payload_data.get("notification_type"),
        android_tag,
        sorted(payload_data.keys()),
    )

    invalid_tokens: list[str] = []

    android_cfg = messaging.AndroidConfig(
        priority="high",
        notification=messaging.AndroidNotification(
            channel_id="teammeeter_notifications",
            sound="default",
            tag=android_tag,
            # POZN.: `click_action` SEM NEDÁVAŤ — pozri komentár v pôvodnom kóde.
        ),
    )

    for token_batch in _chunked(tokens, 500):
        logged_failures = 0
        try:
            if data_message_only:
                # Len `data` → na Androide sa spustí `onBackgroundMessage` a appka
                # zobrazí lokálnu notifikáciu (spoľahlivejšie ako hybrid na pozadí).
                message = messaging.MulticastMessage(
                    tokens=token_batch,
                    data=payload_data,
                    android=android_cfg,
                    apns=messaging.APNSConfig(
                        headers={
                            "apns-priority": "10",
                            "apns-push-type": "alert",
                        },
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(
                                alert=messaging.ApsAlert(title=title, body=body),
                                sound="default",
                            ),
                        ),
                    ),
                )
            else:
                message = messaging.MulticastMessage(
                    tokens=token_batch,
                    notification=messaging.Notification(title=title, body=body),
                    data=payload_data,
                    android=android_cfg,
                    apns=messaging.APNSConfig(
                        headers={
                            "apns-priority": "10",
                            "apns-push-type": "alert",
                        },
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(sound="default"),
                        ),
                    ),
                )
            response = messaging.send_each_for_multicast(message)
            successes = 0
            for index, send_response in enumerate(response.responses):
                if send_response.success:
                    successes += 1
                    continue
                exc = send_response.exception
                if exc is None:
                    continue
                if logged_failures < 5:
                    logger.warning("FCM send failed (index %s): %s", index, exc)
                    logged_failures += 1
                if _should_mark_fcm_token_inactive(exc):
                    invalid_tokens.append(token_batch[index])
            logger.info(
                "FCM batch done: %s/%s success (type=%s)",
                successes,
                len(token_batch),
                payload_data.get("notification_type"),
            )
        except Exception as exc:
            logger.exception("Failed to send push notification batch: %s", exc)

    if invalid_tokens:
        try:
            _mark_tokens_inactive(invalid_tokens)
        except Exception as exc:
            print(f"Failed to mark invalid push tokens inactive: {exc}")
