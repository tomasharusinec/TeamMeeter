import os
import io
from flasgger import swag_from
from flask import request, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, get_current_user_id, load_yaml
from cryptography.fernet import Fernet
from notifications import create_membership_request_notification

conversations_blueprint = Blueprint('/conversations', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))  # AI generated


@conversations_blueprint.route('/', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_conversations"))
@jwt_required()
# Retrieves all conversations for the authenticated user
def get_conversations():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT c.id, c.name, c.created_at
        FROM conversation c
        JOIN participant p ON c.id = p.conversation_id
        WHERE p.user_id = %s
          AND NOT EXISTS (
              SELECT 1
              FROM "group" g
              WHERE g.conversation_id = c.id
          )
    """, (current_user_id,))
    conversations = cursor.fetchall()
    return {"message": "Success", "conversations": conversations}


@conversations_blueprint.route('/', methods=["POST"])
@swag_from(load_yaml("documentation/conversations.yaml", "create_conversation"))
@jwt_required()
# This function was edited using AI (Gemini)
# Creates a new conversation with participants
def create_conversation():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not request.is_json:
        return {"message": "Invalid format! JSON required."}, 400

    name = request.json.get("name")
    participant_ids = request.json.get(
        "participant_ids",
        request.json.get("participants", [])
    )
    participant_usernames = request.json.get("participant_usernames", [])

    if not isinstance(participant_ids, list):
        participant_ids = []
    if not isinstance(participant_usernames, list):
        participant_usernames = []

    resolved_participant_ids = set()
    for participant_id in participant_ids:
        try:
            resolved_participant_ids.add(int(participant_id))
        except:
            continue

    for username in participant_usernames:
        if not isinstance(username, str):
            continue
        cleaned_username = username.strip()
        if not cleaned_username:
            continue
        cursor.execute(
            'SELECT id_registration FROM "user" WHERE username = %s',
            (cleaned_username,)
        )
        user_row = cursor.fetchone()
        if user_row is None:
            return {"message": f'User "{cleaned_username}" not found!'}, 404
        resolved_participant_ids.add(user_row["id_registration"])

    unique_participants = set(resolved_participant_ids)
    unique_participants.add(current_user_id)

    try:
        cursor.execute("""
                       INSERT INTO conversation (name)
                       VALUES (%s) RETURNING id
                       """, (name,))
        conv_id = cursor.fetchone()["id"]

        # Creator is always participant immediately.
        cursor.execute(
            """
            INSERT INTO participant (conversation_id, user_id)
            VALUES (%s, %s)
            ON CONFLICT (conversation_id, user_id) DO NOTHING
            """,
            (conv_id, current_user_id),
        )

        db.commit()

        cursor.execute(
            'SELECT username FROM "user" WHERE id_registration = %s',
            (current_user_id,),
        )
        requester = cursor.fetchone()
        requester_username = requester["username"] if requester else "unknown"

        for pid in unique_participants:
            if pid == current_user_id:
                continue
            try:
                create_membership_request_notification(
                    recipient_user_id=pid,
                    requester_user_id=current_user_id,
                    requester_username=requester_username,
                    target_type="conversation",
                    target_id=conv_id,
                    target_name=name or f"Conversation #{conv_id}",
                )
            except:
                pass
    except Exception as e:
        db.rollback()
        print(f"Error creating conversation: {e}")
        return {"message": "Failed to create conversation!"}, 500

    return {"message": "Conversation created successfully", "conversation_id": conv_id}, 201


@conversations_blueprint.route('/<int:conv_id>', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_conversation"))
@jwt_required()
# Gets details of a specific conversation. User must be a participant.
def get_conversation(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    cursor.execute("""
        SELECT id, name, created_at FROM conversation WHERE id = %s
    """, (conv_id,))
    conversation = cursor.fetchone()
    if conversation is None:
        return {"message": "Conversation not found!"}, 404
    return {"message": "Success", "conversation": conversation}, 200


@conversations_blueprint.route('/<int:conv_id>/participants', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_participants"))
@jwt_required()
# Returns list of participants in a conversation. User must be a participant
def get_participants(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    # Query below was generated using AI (Gemini)
    cursor.execute("""
        SELECT u.id_registration, u.username, us.name, us.surname
        FROM participant p
        JOIN "user" u ON p.user_id = u.id_registration
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE p.conversation_id = %s
    """, (conv_id,))
    participants = cursor.fetchall()
    return {"message": "Success", "participants": participants}, 200


@conversations_blueprint.route('/<int:conv_id>/participants', methods=["POST"])
@swag_from(load_yaml("documentation/conversations.yaml", "add_participant"))
@jwt_required()
# Adds a participant to a private (not a group) conversation. User must be a participant.
def add_participant(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    cursor.execute('SELECT 1 FROM "group" WHERE conversation_id = %s', (conv_id,))
    if cursor.fetchone() is not None:
        return {"message": "This is a group conversation. Please use the group endpoints to add members!"}, 403

    if not request.is_json:
        return {"message": "Invalid format!"}, 400

    user_id = request.json.get("user_id")
    username = request.json.get("username")

    if user_id is None and (username is None or not str(username).strip()):
        return {"message": "user_id or username is required!"}, 400

    if user_id is None:
        cursor.execute(
            'SELECT id_registration FROM "user" WHERE username = %s',
            (str(username).strip(),)
        )
        user_row = cursor.fetchone()
        if user_row is None:
            return {"message": "User not found!"}, 404
        user_id = user_row["id_registration"]

    try:
        cursor.execute(
            'SELECT id_registration FROM "user" WHERE id_registration = %s',
            (user_id,)
        )
        if cursor.fetchone() is None:
            return {"message": "User not found!"}, 404

        cursor.execute(
            "SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s",
            (conv_id, user_id),
        )
        if cursor.fetchone() is not None:
            return {"message": "User is already a participant!"}, 409

        cursor.execute(
            """
            SELECT 1
            FROM membership_request_notification mrn
            JOIN user_notification un ON mrn.notification_id = un.notification_id
            WHERE un.user_id = %s
              AND mrn.target_type = 'conversation'
              AND mrn.target_id = %s
              AND mrn.status = 'pending'
            """,
            (user_id, conv_id),
        )
        if cursor.fetchone() is not None:
            return {"message": "Pending conversation invitation already exists!"}, 409

        cursor.execute(
            'SELECT username FROM "user" WHERE id_registration = %s',
            (current_user_id,),
        )
        requester = cursor.fetchone()
        requester_username = requester["username"] if requester else "unknown"

        cursor.execute("SELECT name FROM conversation WHERE id = %s", (conv_id,))
        conv_data = cursor.fetchone()
        conversation_name = conv_data["name"] if conv_data and conv_data["name"] else f"Conversation #{conv_id}"

        create_membership_request_notification(
            recipient_user_id=user_id,
            requester_user_id=current_user_id,
            requester_username=requester_username,
            target_type="conversation",
            target_id=conv_id,
            target_name=conversation_name,
        )
    except:
        db.rollback()
        return {"message": "Failed to create invitation!"}, 500

    return {"message": "Invitation sent successfully. User must accept it."}, 200


@conversations_blueprint.route('/<int:conv_id>/participants/<int:user_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "remove_participant"))
@jwt_required()
# Removes a participant from a private (not a group) conversation. User must be a participant.
def remove_participant(conv_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    cursor.execute('SELECT 1 FROM "group" WHERE conversation_id = %s', (conv_id,))
    if cursor.fetchone() is not None:
        return {"message": "This is a group conversation. Please use the group endpoints to remove members!"}, 403

    try:
        cursor.execute("""
            DELETE FROM participant WHERE conversation_id = %s AND user_id = %s
        """, (conv_id, user_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to remove participant!"}, 500

    return {"message": "Participant removed successfully"}, 200


@conversations_blueprint.route('/<int:conv_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "delete_conversation"))
@jwt_required()
# Deletes a private (not a group) conversation. User must be a participant.
def delete_conversation(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    cursor.execute('SELECT 1 FROM "group" WHERE conversation_id = %s', (conv_id,))
    if cursor.fetchone() is not None:
        return {"message": "This is a group conversation. Please delete the group itself using group endpoints!"}, 403

    try:
        cursor.execute("DELETE FROM conversation WHERE id = %s", (conv_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete conversation!"}, 500

    return {"message": "Conversation deleted successfully"}, 200


@conversations_blueprint.route('/<int:conv_id>/messages', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_messages"))
@jwt_required()
# This function was generated using AI (Gemini) and manually refined
# Gets all messages from a conversation and decrypts them. User must be participant.
def get_messages(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}, 403

    cursor.execute("""
        SELECT m.id, m.conversation_id, m.sender_id, m.text, u.username AS sender_username,
               CASE WHEN f.id IS NOT NULL THEN
                   json_build_object('id', f.id, 'name', f.name, 'extension', f.extension)
               ELSE NULL END AS file
        FROM message m
        JOIN "user" u ON m.sender_id = u.id_registration
        LEFT JOIN file f ON m.file_id = f.id
        WHERE m.conversation_id = %s
        ORDER BY m.id ASC
    """, (conv_id,))
    messages = cursor.fetchall()

    for msg in messages:
        try:
            decrypted_bytes = cipher_suite.decrypt(bytes(msg["text"]))
            msg["text"] = decrypted_bytes.decode()
        except:
            msg["text"] = "[Decryption Error]"

    return {"message": "Success", "messages": messages}, 200


@conversations_blueprint.route('/<int:conv_id>/messages/<int:message_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "delete_message"))
@jwt_required()
# This function was generated using AI (Gemini)
# Deletes a specific message. User must be the sender.
def delete_message(conv_id, message_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT m.sender_id
        FROM message m
        JOIN conversation c ON m.conversation_id = c.id
        WHERE m.id = %s AND m.conversation_id = %s
    """, (message_id, conv_id))
    message = cursor.fetchone()
    if message is None:
        return {"message": "Message not found!"}, 404

    can_delete = False

    if message["sender_id"] == current_user_id:
        can_delete = True

    if not can_delete:
        return {"message": "You don't have permission to delete this message!"}, 403

    try:
        cursor.execute("DELETE FROM message WHERE id = %s", (message_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete message!"}, 500

    return {"message": "Message deleted successfully"}, 200


@conversations_blueprint.route('/files/<int:file_id>', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_file"))
@jwt_required()
# Downloads an attached file. User must be a participant of the conversation.
def get_file(file_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT f.name, f.extension, f.content, m.conversation_id 
        FROM file f
        JOIN message m ON f.id = m.file_id
        WHERE f.id = %s
    """, (file_id,))
    file_info = cursor.fetchone()

    if not file_info:
        return {"message": "File not found!"}, 404

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (file_info["conversation_id"], current_user_id))

    if cursor.fetchone() is None:
        return {"message": "You don't have access to this conversation!"}, 403

    if file_info["content"] is None:
        return {"message": "File content is empty!"}, 404

    # Lines below were written with help of AI
    file_bytes = bytes(file_info["content"])
    filename = f'{file_info["name"]}.{file_info["extension"]}'
    file = io.BytesIO(file_bytes)

    return send_file(file, download_name=filename)


@conversations_blueprint.route('/files/<int:file_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "delete_file"))
@jwt_required()
# This function was generated using AI (Gemini)
# Deletes an attached file. User must be the sender of the message.
def delete_file(file_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT m.sender_id, m.conversation_id 
        FROM file f
        JOIN message m ON f.id = m.file_id
        JOIN conversation c ON m.conversation_id = c.id
        WHERE f.id = %s
    """, (file_id,))
    file_info = cursor.fetchone()

    if not file_info:
        return {"message": "File not found!"}, 404

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (file_info["conversation_id"], current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You don't have access to this conversation!"}, 403

    can_delete = False

    if file_info["sender_id"] == current_user_id:
        can_delete = True

    if not can_delete:
        return {"message": "You don't have permission to delete this file!"}, 403

    try:
        cursor.execute("DELETE FROM file WHERE id = %s", (file_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete file!"}, 500

    return {"message": "File deleted successfully"}, 200