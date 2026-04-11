import os
from flasgger import swag_from
from flask import request, Blueprint
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from cryptography.fernet import Fernet
from helper_func import db, get_current_user_id, is_group_member, check_permission, load_yaml
from websocket_handler import broadcast_to_conversation, create_message_notification, get_db_connection, create_activity_notification

sync_blueprint = Blueprint('sync', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))

@sync_blueprint.route('/pull', methods=["GET"])
@jwt_required()
@swag_from(load_yaml("documentation/sync.yaml", "sync_pull"))
# Function below was generated with AI with manual refinements
# Pulls new messages, activities, and conversations
def sync_pull():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if current_user_id is None:
        return {"message": "User not found!"}, 401

    last_message_id = request.args.get("last_message_id", 0, type=int)
    last_activity_id = request.args.get("last_activity_id", 0, type=int)
    conversation_id = request.args.get("conversation_id", None, type=int)

    if conversation_id:
        cursor.execute(
            "SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s",
            (conversation_id, current_user_id),
        )
        if cursor.fetchone() is None:
            return {"message": "You are not a participant of this conversation!"}, 403

        cursor.execute("""
            SELECT m.id, m.conversation_id, m.sender_id, m.text, u.username AS sender_username
            FROM message m
            JOIN "user" u ON m.sender_id = u.id_registration
            WHERE m.conversation_id = %s AND m.id > %s
            ORDER BY m.id ASC
        """, (conversation_id, last_message_id))
    else:
        cursor.execute("""
            SELECT m.id, m.conversation_id, m.sender_id, m.text, u.username AS sender_username
            FROM message m
            JOIN "user" u ON m.sender_id = u.id_registration
            JOIN participant p ON m.conversation_id = p.conversation_id
            WHERE p.user_id = %s AND m.id > %s
            ORDER BY m.id ASC
        """, (current_user_id, last_message_id))

    messages = cursor.fetchall()

    for msg in messages:
        try:
            decrypted = cipher_suite.decrypt(bytes(msg["text"]))
            msg["text"] = decrypted.decode()
        except:
            msg["text"] = "[Decryption Error]"

    cursor.execute("""
        SELECT DISTINCT a.id_activity, a.name, a.description, a.creation_date, a.deadline, a.creator_id, a.group_id, u.username AS creator_username
        FROM activity a
        JOIN "user" u ON a.creator_id = u.id_registration
        JOIN group_member gm ON a.group_id = gm.group_id
        WHERE gm.user_id = %s AND a.id_activity > %s
        ORDER BY a.id_activity ASC
    """, (current_user_id, last_activity_id))
    activities = cursor.fetchall()

    cursor.execute("""
        SELECT c.id, c.name, c.created_at
        FROM conversation c
        JOIN participant p ON c.id = p.conversation_id
        WHERE p.user_id = %s
        ORDER BY c.id ASC
    """, (current_user_id,))
    conversations = cursor.fetchall()

    cursor.execute("SELECT CURRENT_TIMESTAMP AS server_time")
    server_time = cursor.fetchone()["server_time"]

    return {
        "message": "Success",
        "messages": messages,
        "activities": activities,
        "conversations": conversations,
        "server_time": server_time.isoformat() if server_time else None,
    }, 200

# Function below was polished with AI (Gemini)
# Creates a new encrypted message. User must be a participant of conversation.
def sync_create_message(user_id, data):
    conv_id = data.get("conversation_id")
    text = data.get("text")

    if not conv_id or not text:
        return {
            "message": "conversation_id and text are required"
        }

    cursor.execute(
        "SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s",
        (conv_id, user_id),
    )
    if cursor.fetchone() is None:
        return {
            "message": "You are not a participant of this conversation!"
        }

    encrypted = cipher_suite.encrypt(text.encode())
    cursor.execute("""
        INSERT INTO message (conversation_id, sender_id, text)
        VALUES (%s, %s, %s) RETURNING id
    """, (conv_id, user_id, encrypted))
    message_id = cursor.fetchone()["id"]
    db.commit()

    try:
        cursor.execute('SELECT username FROM "user" WHERE id_registration = %s', (user_id,))
        sender = cursor.fetchone()
        if sender:
            sender_username = sender["username"]
        else:
            sender_username = "unknown"

        broadcast_to_conversation(conv_id, {
            "type": "new_message",
            "id": message_id,
            "conversation_id": conv_id,
            "sender_id": user_id,
            "sender_username": sender_username,
            "text": text,
        })

        ws_conn = get_db_connection()
        try:
            create_message_notification(ws_conn, message_id, conv_id, user_id)
        finally:
            ws_conn.close()
    except:
        pass

    return {"message": f"Message {message_id} was successfully created!"}