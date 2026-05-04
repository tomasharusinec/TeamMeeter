import json
import logging
import os
import threading
from typing import Optional, Tuple
import psycopg2
import jwt
from psycopg2.extras import RealDictCursor
from flask_sock import Sock
from cryptography.fernet import Fernet
from dotenv import load_dotenv
from push_notifications import send_push_to_users

load_dotenv()
logger = logging.getLogger(__name__)
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))
JWT_SECRET = os.getenv("JWT_SECRET_KEY")

connected_clients: dict[int, set] = {} # AI generated
clients_lock = threading.Lock() # AI generated
sock = Sock()

# Function below was AI generated
# Creates and returns a new PostgreSQL DB connection. Requires env credentials.
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("MY_PASS"),
        database=os.getenv("DB_NAME", "TeamsMeeter"),
    )

# Creates a DB cursor returning dict results
def get_cursor(connection):
    return connection.cursor(cursor_factory=RealDictCursor)

# Finds user ID based on username
def get_user_id(c, uname):
    cur = get_cursor(c)
    cur.execute('SELECT id_registration FROM "user" WHERE username = %s', (uname,))
    res = cur.fetchone()
    cur.close()
    if res is not None:
        return res["id_registration"]
    else:
        return None

# Gets all participant IDs for a conversation
def get_participants(c, conv_id):
    cur = get_cursor(c)
    cur.execute("SELECT user_id FROM participant WHERE conversation_id = %s", (conv_id,))
    rows = cur.fetchall()
    cur.close()

    participants = []
    for user_id in rows:
        participants.append(user_id["user_id"])
    return participants

# Function below was generated using
# Registers new websocket connection for an authenticated user
def register(user_id: int, ws):
    with clients_lock:
        if user_id not in connected_clients:
            connected_clients[user_id] = set()
        connected_clients[user_id].add(ws)

# Function below was generated using AI
# Removes terminated websocket connection from active clients
def unregister(user_id: int, ws):
    with clients_lock:
        sockets = connected_clients.get(user_id)
        if sockets:
            sockets.discard(ws)
            if not sockets:
                del connected_clients[user_id]

# Function below was refined using AI (Gemini)
# Creates notifications for all participants except sender
def create_message_notification(conn, message_id: int, conversation_id: int, sender_id: int):
    try:
        participant_ids = get_participants(conn, conversation_id)
        recipient_ids = []
        for uid in participant_ids:
            if uid != sender_id:
                recipient_ids.append(uid)

        if len(recipient_ids) == 0:
            return

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """INSERT INTO notification (type)
                   VALUES (1) RETURNING id_notification, created_at""",
            )
            notif = cur.fetchone()
            notification_id = notif["id_notification"]
            created_at = notif["created_at"]

            for uid in recipient_ids:
                cur.execute(
                    """INSERT INTO user_notification (notification_id, user_id)
                       VALUES (%s, %s)""",
                    (notification_id, uid),
                )

            cur.execute(
                """INSERT INTO message_notification (notification_id, message_id)
                   VALUES (%s, %s)""",
                (notification_id, message_id),
            )
            conn.commit()

        notif_payload = {
            "type": "new_notification",
            "notification_id": notification_id,
            "notification_type": 1,
            "message_id": message_id,
            "conversation_id": conversation_id,
            "created_at": created_at.isoformat() if created_at else None,
        }
        broadcast_to_users(recipient_ids, notif_payload)
        preview = text_preview(conn, message_id)
        conv_name, group_id_for_push = conversation_display_and_group(
            conn, conversation_id
        )
        su = sender_username(conn, sender_id)
        title = f"New message in {conv_name}"
        body = f"{su}: {preview}"
        # Iba minimálna sada údajov, ktoré Flutter potrebuje na navigáciu po klepnutí.
        # `notification` blok (title/body) sa posiela samostatne v `send_push_to_users`,
        # takže ich do `data` nedávame (zbytočne by zaberali z 4 KiB FCM limitu).
        push_data = {
            "notification_type": "1",
            "notification_id": str(notification_id),
            "conversation_id": str(conversation_id),
            "conversation_name": conv_name,
            "sender_username": su,
            "message_id": str(message_id),
            "chat_kind": "group" if group_id_for_push is not None else "direct",
        }
        if group_id_for_push is not None:
            push_data["group_id"] = str(group_id_for_push)
        send_push_to_users(
            recipient_ids,
            title=title,
            body=body,
            data=push_data,
        )

    except Exception:
        logger.exception(
            "create_message_notification failed (conv=%s msg=%s sender=%s)",
            conversation_id,
            message_id,
            sender_id,
        )
        try:
            conn.rollback()
        except Exception:
            pass

# This function was created based on create_message_notification function
# Creates notifications for new group activities for all members except creator
def create_activity_notification(conn, activity_id: int, group_id: int, creator_id: int, activity_name: str = ""):
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT user_id FROM group_member WHERE group_id = %s",
                (group_id,),
            )

            member_ids = []
            for user_id in cur.fetchall():
                member_ids.append(user_id["user_id"])

            recipient_ids = []
            for uid in member_ids:
                if uid != creator_id:
                    recipient_ids.append(uid)

            if len(recipient_ids) == 0:
                return

            cur.execute(
                """INSERT INTO notification (type)
                   VALUES (2) RETURNING id_notification, created_at""",
            )
            notif = cur.fetchone()
            notification_id = notif["id_notification"]
            created_at = notif["created_at"]

            for uid in recipient_ids:
                cur.execute(
                    """INSERT INTO user_notification (notification_id, user_id)
                       VALUES (%s, %s)""",
                    (notification_id, uid),
                )

            cur.execute(
                """INSERT INTO activity_notification (notification_id, activity_id)
                   VALUES (%s, %s)""",
                (notification_id, activity_id),
            )
            conn.commit()

        notif_payload = {
            "type": "new_notification",
            "notification_id": notification_id,
            "notification_type": 2,
            "activity_id": activity_id,
            "activity_name": activity_name,
            "group_id": group_id,
            "created_at": created_at.isoformat() if created_at else None,
        }
        broadcast_to_users(recipient_ids, notif_payload)
        grp_name = group_name(conn, group_id)
        activity_label = activity_name or f"Activity #{activity_id}"
        send_push_to_users(
            recipient_ids,
            title=f"New activity {activity_label}",
            body=f"New group activity in {grp_name}",
            data={
                "notification_type": "2",
                "notification_id": str(notification_id),
                "group_id": str(group_id),
                "group_name": grp_name,
                "activity_id": str(activity_id),
                "activity_name": activity_label,
            },
        )

    except:
        try:
            conn.rollback()
        except:
            pass

# Function below was polished with AI (Gemini)
# Handles text message via websocket, saves to DB and broadcasts. Requires group membership.
def handle_send_message(ws, conn, user_id, username, data):
    conv_id = data.get("conversation_id")
    text = data.get("text")

    if conv_id is None or text is None:
        error_payload = {
            "type": "error",
            "message": "conversation_id and text are required"
        }
        json_message = json.dumps(error_payload)
        ws.send(json_message)
        return

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s",
                (conv_id, user_id),
            )
            if cur.fetchone() is None:
                ws.send(json.dumps({
                    "type": "error",
                    "message": "You are not a participant of this conversation",
                }))
                return

            encrypted = cipher_suite.encrypt(text.encode())
            cur.execute(
                """INSERT INTO message (conversation_id, sender_id, text)
                   VALUES (%s, %s, %s) RETURNING id""",
                (conv_id, user_id, encrypted),
            )
            message_id = cur.fetchone()["id"]
            conn.commit()

        broadcast_payload = {
            "type": "new_message",
            "id": message_id,
            "conversation_id": conv_id,
            "sender_id": user_id,
            "sender_username": username,
            "text": text,
        }
        broadcast_to_conversation(conv_id, broadcast_payload, db_conn=conn)
        create_message_notification(conn, message_id, conv_id, user_id)

    except Exception as e:
        conn.rollback()
        error_payload = {
            "type": "error",
            "message": f"Failed to send message: {str(e)}"
        }
        json_payload = json.dumps(error_payload)
        ws.send(json_payload)


def sender_username(conn, sender_id: int) -> str:
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute('SELECT username FROM "user" WHERE id_registration = %s', (sender_id,))
            row = cur.fetchone()
            if row and row.get("username"):
                return row["username"]
    except:
        pass
    return "Pouzivatel"


def text_preview(conn, message_id: int) -> str:
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT text FROM message WHERE id = %s", (message_id,))
            row = cur.fetchone()
            if row and row.get("text"):
                decrypted = cipher_suite.decrypt(bytes(row["text"])).decode()
                clean = decrypted.strip()
                if clean:
                    return clean[:120]
    except:
        pass
    return "Poslal(a) novu spravu"


def conversation_display_and_group(
    conn, conversation_id: int
) -> Tuple[str, Optional[int]]:
    """Human-readable chat title for push + group id when this chat is a group channel."""
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT c.name AS conv_name, g.id_group AS group_id, g.name AS group_name
                FROM conversation c
                LEFT JOIN "group" g ON g.conversation_id = c.id
                WHERE c.id = %s
                """,
                (conversation_id,),
            )
            row = cur.fetchone()
            if not row:
                return (f"Conversation #{conversation_id}", None)
            gn = row.get("group_name")
            if isinstance(gn, str) and gn.strip():
                return (gn.strip(), row.get("group_id"))
            cn = row.get("conv_name")
            if isinstance(cn, str) and cn.strip():
                return (cn.strip(), row.get("group_id"))
            cur.execute(
                """
                SELECT string_agg(u.username, ', ' ORDER BY u.username) AS names
                FROM participant p
                JOIN "user" u ON u.id_registration = p.user_id
                WHERE p.conversation_id = %s
                """,
                (conversation_id,),
            )
            row2 = cur.fetchone()
            names = row2.get("names") if row2 else None
            if isinstance(names, str) and names.strip():
                return (names.strip(), None)
    except Exception:
        pass
    return (f"Conversation #{conversation_id}", None)


def group_name(conn, group_id: int) -> str:
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute('SELECT name FROM "group" WHERE id_group = %s', (group_id,))
            row = cur.fetchone()
            if row:
                name = row.get("name")
                if isinstance(name, str):
                    cleaned = name.strip()
                    if cleaned:
                        return cleaned
    except:
        pass
    return f"Group #{group_id}"

# Function below was polished with AI (Gemini)
# Handles message with file attachment via websocket. Requires group membership.
def handle_send_message_with_file(ws, conn, user_id, username, data):
    conv_id = data.get("conversation_id")
    text = data.get("text", "")
    file_name = data.get("file_name")
    file_extension = data.get("file_extension")

    if conv_id is None or not file_name or not file_extension:
        error_payload = {
            "type": "error",
            "message": "conversation_id, file_name, and file_extension are required"
        }
        json_string = json.dumps(error_payload)
        ws.send(json_string)
        return

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s",
                (conv_id, user_id),
            )
            if cur.fetchone() is None:
                access_denied_payload = {
                    "type": "error",
                    "message": "You are not a participant of this conversation"
                }
                json_payload = json.dumps(access_denied_payload)
                ws.send(json_payload)
                return

        ws.send(json.dumps({"type": "awaiting_file"}))
        file_content = ws.receive(timeout=30)
        if file_content is None:
            no_data_payload = {
                "type": "error",
                "message": "No file data received"
            }
            json_output = json.dumps(no_data_payload)
            ws.send(json_output)
            return

        if isinstance(file_content, str):
            file_content = file_content.encode()

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """INSERT INTO file (name, extension, content)
                   VALUES (%s, %s, %s) RETURNING id""",
                (file_name, file_extension, file_content),
            )
            file_id = cur.fetchone()["id"]

            encrypted = cipher_suite.encrypt(text.encode()) if text else cipher_suite.encrypt(b"")
            cur.execute(
                """INSERT INTO message (conversation_id, sender_id, file_id, text)
                   VALUES (%s, %s, %s, %s) RETURNING id""",
                (conv_id, user_id, file_id, encrypted),
            )
            message_id = cur.fetchone()["id"]
            conn.commit()

        broadcast_payload = {
            "type": "new_message",
            "id": message_id,
            "conversation_id": conv_id,
            "sender_id": user_id,
            "sender_username": username,
            "text": text,
            "file": {
                "id": file_id,
                "name": file_name,
                "extension": file_extension,
            },
        }
        broadcast_to_conversation(conv_id, broadcast_payload, db_conn=conn)
        create_message_notification(conn, message_id, conv_id, user_id)

    except Exception as e:
        conn.rollback()
        error_details = {
            "type": "error",
            "message": f"Failed to send message with file: {str(e)}"
        }
        json_payload = json.dumps(error_details)
        ws.send(json_payload)

# Function below was generated using AI (Gemini)
# Sends payload to all active websocket connections of specified users
def broadcast_to_users(user_ids: list[int], payload: dict):
    message_text = json.dumps(payload, default=str)
    with clients_lock:
        for uid in user_ids:
            sockets = connected_clients.get(uid, set())
            dead = set()
            for ws in sockets:
                try:
                    ws.send(message_text)
                except:
                    dead.add(ws)
            sockets -= dead

# Function below was generated using AI (Gemini)
# Sends payload to all online participants of a conversation
def broadcast_to_conversation(conversation_id: int, payload: dict, db_conn=None):
    if db_conn is None:
        own_conn = True
    else:
        own_conn = False

    if own_conn:
        db_conn = get_db_connection()

    try:
        participant_ids = get_participants(db_conn, conversation_id)
        message_text = json.dumps(payload, default=str)

        with clients_lock:
            for uid in participant_ids:
                sockets = connected_clients.get(uid, set())
                dead = set()
                for ws in sockets:
                    try:
                        ws.send(message_text)
                    except:
                        dead.add(ws)
                sockets -= dead
    finally:
        if own_conn:
            db_conn.close()

# Function below was generated using AI with manual refinements
# Main websocket endpoint handling auth and message routing.
@sock.route("/websocket")
def websocket_endpoint(ws):
    user_id = None
    username = None
    conn = get_db_connection()

    try:
        raw = ws.receive(timeout=30)
        if raw is None:
            return

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            ws.send(json.dumps({"type": "error", "message": "Invalid JSON"}))
            return

        if data.get("type") != "auth" or "token" not in data:
            auth_error = {
                "type": "error",
                "message": "First message must be auth with token"
            }
            json_response = json.dumps(auth_error)
            ws.send(json_response)
            return

        try:
            decoded = jwt.decode(
                data["token"],
                JWT_SECRET,
                algorithms=["HS256"],
            )
            username = decoded.get("sub")
        except jwt.ExpiredSignatureError:
            ws.send(json.dumps({"type": "error", "message": "Token expired"}))
            return
        except jwt.InvalidTokenError:
            ws.send(json.dumps({"type": "error", "message": "Invalid token"}))
            return

        user_id = get_user_id(conn, username)
        if user_id is None:
            ws.send(json.dumps({"type": "error", "message": "User not found"}))
            return

        register(user_id, ws)
        auth_payload = {
            "type": "auth_success",
            "user_id": user_id,
            "username": username,
        }
        json_response = json.dumps(auth_payload)
        ws.send(json_response)

        while True:
            raw = ws.receive()
            if raw is None:
                break

            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                ws.send(json.dumps({"type": "error", "message": "Invalid JSON"}))
                continue

            msg_type = data.get("type")
            if msg_type == "send_message":
                handle_send_message(ws, conn, user_id, username, data)
            elif msg_type == "send_message_with_file":
                handle_send_message_with_file(ws, conn, user_id, username, data)
            else:
                unknown_type_payload = {
                    "type": "error",
                    "message": f"Unknown message type: {msg_type}"
                }
                json_response = json.dumps(unknown_type_payload)
                ws.send(json_response)
    except:
        pass

    finally:
        if user_id is not None:
            unregister(user_id, ws)
        try:
            conn.close()
        except:
            pass