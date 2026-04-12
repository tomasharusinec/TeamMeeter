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


@sync_blueprint.route('/push', methods=["POST"])
@jwt_required()
@swag_from(load_yaml("documentation/sync.yaml", "sync_push"))
# Logic of the function below was designed via AI consultation, manually implemented and AI refined
# Processes sync operations (create/delete messages/activities)
def sync_push():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if current_user_id is None:
        return {"message": "User not found!"}, 401

    try:
        operations = request.json.get("operations", [])
    except:
        return {"message": "Invalid format!"}, 400

    if not isinstance(operations, list):
        return {"message": "operations must be a list!"}, 400

    results = []

    for operation in operations:
        operation_type = operation.get("op")
        client_id = operation.get("client_id", "unknown")

        try:
            if operation_type == "create_message":
                result = sync_create_message(current_user_id, operation)
            elif operation_type == "delete_message":
                result = sync_delete_message(current_user_id, operation)
            elif operation_type == "create_activity":
                result = sync_create_activity(current_user_id, operation)
            elif operation_type == "update_activity":
                result = sync_update_activity(current_user_id, operation)
            elif operation_type == "delete_activity":
                result = sync_delete_activity(current_user_id, operation)
            else:
                result = {"status": "error", "reason": f"unknown operation: {operation_type}"}
        except Exception as e:
            db.rollback()
            result = {"status": "error", "reason": str(e)}

        result["client_id"] = client_id
        results.append(result)

    return {"message": "Sync completed", "results": results}, 200


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


# Function below was polished with AI (Gemini)
# Deletes a message by ID. User must be sender or have 'delete_messages' permission.
def sync_delete_message(user_id, data):
    message_id = data.get("message_id")
    conv_id = data.get("conversation_id")

    if not message_id:
        return {"message": "message_id is required"}

    cursor.execute("""
        SELECT m.sender_id
        FROM message m
        JOIN conversation c ON m.conversation_id = c.id
        WHERE m.id = %s
    """, (message_id,))
    message = cursor.fetchone()

    if message is None:
        return {"message": "message_not_found"}

    can_delete = False
    if message["sender_id"] == user_id:
        can_delete = True
    elif conv_id:
        cursor.execute(
            'SELECT id_group FROM "group" WHERE conversation_id = %s', (conv_id,)
        )
        group_data = cursor.fetchone()
        if group_data and check_permission(user_id, group_data["id_group"], "delete_messages"):
            can_delete = True

    if not can_delete:
        return {"status": "conflict", "reason": "no_permission"}

    cursor.execute("DELETE FROM message WHERE id = %s", (message_id,))
    db.commit()
    return {"status": "deleted", "server_id": message_id}


# Function below was generated with AI (Gemini)
# Creates a new activity in a group. Requires group membership and 'create_activity' permission.
def sync_create_activity(user_id, data):
    group_id = data.get("group_id")
    name = data.get("name")
    description = data.get("description")
    deadline = data.get("deadline")

    if not name:
        return {"status": "error", "reason": "name is required"}

    if group_id:
        if not is_group_member(user_id, group_id):
            return {"status": "conflict", "reason": "not_a_group_member"}

        if not check_permission(user_id, group_id, "create_activity"):
            return {"status": "conflict", "reason": "no_permission"}

    cursor.execute("""
        INSERT INTO activity (name, description, deadline, creator_id, group_id)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id_activity
    """, (name, description, deadline, user_id, group_id))
    activity_id = cursor.fetchone()["id_activity"]
    db.commit()

    if group_id:
        try:
            ws_conn = get_db_connection()
            try:
                create_activity_notification(ws_conn, activity_id, group_id, user_id, name)
            finally:
                ws_conn.close()
        except:
            pass

    return {"message": f"Successfully created activity with id {activity_id}!"}

# Function below was generated using AI (Gemini) with manual refinements
# Updates an existing activity. Requires being creator or having 'edit_activity' permission.
def sync_update_activity(user_id, data):
    activity_id = data.get("activity_id")
    name = data.get("name")
    description = data.get("description")
    deadline = data.get("deadline")

    if not activity_id:
        return {"status": "error", "reason": "activity_id is required"}

    cursor.execute(
        "SELECT group_id, creator_id FROM activity WHERE id_activity = %s",
        (activity_id,),
    )
    activity = cursor.fetchone()
    if activity is None:
        return {"message": "activity_not_found"}

    group_id = activity["group_id"]
    creator_id = activity["creator_id"]

    if not is_group_member(user_id, group_id):
        return {"message": "User is not a group member!"}

    if user_id == creator_id:
        is_creator = True
    else:
        is_creator = False
    if not is_creator and not check_permission(user_id, group_id, "edit_activity"):
        return {"message": "You dont have permissions to edit activity!"}

    client_ts = data.get("client_timestamp")
    if client_ts:
        cursor.execute(
            "SELECT creation_date FROM activity WHERE id_activity = %s",
            (activity_id,),
        )
        current = cursor.fetchone()
        if current is None:
            return {"message": "Activity was already deleted by another user!"}

    cursor.execute("""
        UPDATE activity SET
            name = COALESCE(%s, name),
            description = COALESCE(%s, description),
            deadline = COALESCE(%s, deadline)
        WHERE id_activity = %s
    """, (name, description, deadline, activity_id))
    db.commit()

    return {"message": f"Successfully created activity with id {activity_id}!"}

# Function below was generated using AI (Gemini) with manual refinements
# Deletes an activity. Requires being creator or having 'delete_activity' permission.
def sync_delete_activity(user_id, data):
    activity_id = data.get("activity_id")

    if not activity_id:
        return {"message": "Activity_id is required!"}

    cursor.execute(
        "SELECT group_id, creator_id FROM activity WHERE id_activity = %s",
        (activity_id,),
    )
    activity = cursor.fetchone()

    if activity is None:
        return {"message": "Activity was not found!"}

    group_id = activity["group_id"]
    creator_id = activity["creator_id"]

    if not is_group_member(user_id, group_id):
        return {"message": "User is not a group member!"}

    if user_id == creator_id:
        is_creator = True
    else:
        is_creator = False
    if not is_creator and not check_permission(user_id, group_id, "delete_activity"):
        return {"status": "conflict", "reason": "no_permission"}

    cursor.execute("DELETE FROM activity WHERE id_activity = %s", (activity_id,))
    db.commit()

    return {"status": "deleted", "server_id": activity_id}