import json
import os
import threading
import psycopg2
from psycopg2.extras import RealDictCursor
from flask_sock import Sock
from cryptography.fernet import Fernet
from dotenv import load_dotenv

load_dotenv()
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))
JWT_SECRET = os.getenv("JWT_SECRET_KEY")

connected_clients: dict[int, set] = {} # AI generated
clients_lock = threading.Lock() # AI generated
sock = Sock()

# Function below was AI generated
# Creates and returns a new PostgreSQL DB connection. Requires env credentials.
def get_db_connection():
    return psycopg2.connect(
        host="localhost",
        port="5432",
        user="postgres",
        password=os.getenv("MY_PASS"),
        database="TeamsMeeter",
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

    except:
        try:
            conn.rollback()
        except:
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
        # broadcast_to_conversation(conv_id, broadcast_payload, db_conn=conn) TBA
        create_message_notification(conn, message_id, conv_id, user_id)

    except Exception as e:
        conn.rollback()
        error_payload = {
            "type": "error",
            "message": f"Failed to send message: {str(e)}"
        }
        json_payload = json.dumps(error_payload)
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