import io
import os
from flasgger import swag_from
from flask import request, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, get_current_user_id, check_permission, load_yaml
from cryptography.fernet import Fernet

conversations_blueprint = Blueprint('/conversations', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))

@conversations_blueprint.route('/', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_conversations"))
@jwt_required()
def get_conversations():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT c.id, c.name, c.created_at
        FROM conversation c
        JOIN participant p ON c.id = p.conversation_id
        WHERE p.user_id = %s
    """, (current_user_id,))
    conversations = cursor.fetchall()
    return {"message": "Success", "conversations": conversations}

@conversations_blueprint.route('/', methods=["POST"])
@swag_from(load_yaml("documentation/conversations.yaml", "create_conversation"))
@jwt_required()
def create_conversation():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not request.is_json:
        return {"message": "Invalid format! JSON required."}, 400

    name = request.json.get("name")

    participant_ids = request.json.get("participant_ids", request.json.get("participants", []))

    if not isinstance(participant_ids, list):
        participant_ids = []

    unique_participants = set(participant_ids)
    unique_participants.add(current_user_id)

    try:
        cursor.execute("""
                       INSERT INTO conversation (name)
                       VALUES (%s) RETURNING id
                       """, (name,))
        conv_id = cursor.fetchone()["id"]

        for pid in unique_participants:
            cursor.execute("""
                           INSERT INTO participant (conversation_id, user_id)
                           VALUES (%s, %s)
                           """, (conv_id, pid))

        db.commit()
    except Exception as e:
        db.rollback()
        print(f"Error creating conversation: {e}")
        return {"message": "Failed to create conversation!"}, 500

    return {"message": "Conversation created successfully", "conversation_id": conv_id}, 201

@conversations_blueprint.route('/<int:conv_id>', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_conversation"))
@jwt_required()
def get_conversation(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}

    cursor.execute("""
        SELECT id, name, created_at FROM conversation WHERE id = %s
    """, (conv_id,))
    conversation = cursor.fetchone()
    if conversation is None:
        return {"message": "Conversation not found!"}
    return {"message": "Success", "conversation": conversation}

@conversations_blueprint.route('/<int:conv_id>/participants', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_participants"))
@jwt_required()
def get_participants(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}

    cursor.execute("""
        SELECT u.id_registration, u.username, us.name, us.surname
        FROM participant p
        JOIN "user" u ON p.user_id = u.id_registration
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE p.conversation_id = %s
    """, (conv_id,))
    participants = cursor.fetchall()
    return {"message": "Success", "participants": participants}

@conversations_blueprint.route('/<int:conv_id>/participants', methods=["POST"])
@swag_from(load_yaml("documentation/conversations.yaml", "add_participant"))
@jwt_required()
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

    try:
        user_id = request.json["user_id"]
    except:
        return {"message": "Invalid format!"}, 400

    try:
        cursor.execute("""
            INSERT INTO participant (conversation_id, user_id) VALUES (%s, %s)
        """, (conv_id, user_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to add participant!"}, 500

    return {"message": "Participant added successfully"}, 200

@conversations_blueprint.route('/<int:conv_id>/participants/<int:user_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "remove_participant"))
@jwt_required()
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
def get_messages(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You are not a participant of this conversation!"}

    cursor.execute("""
        SELECT m.id, m.conversation_id, m.sender_id, m.text,
               u.username AS sender_username
        FROM message m
        JOIN "user" u ON m.sender_id = u.id_registration
        WHERE m.conversation_id = %s
        ORDER BY m.id ASC
    """, (conv_id,))
    messages = cursor.fetchall()

    for msg in messages:
        try:
            decrypted_bytes = cipher_suite.decrypt(bytes(msg["text"]))
            msg["text"] = decrypted_bytes.decode()
        except Exception:
            msg["text"] = "[Decryption Error]"


    return {"message": "Success", "messages": messages}


@conversations_blueprint.route('/<int:conv_id>/messages/<int:message_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "delete_message"))
@jwt_required()
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
        return {"message": "Message not found!"}

    can_delete = False

    if message["sender_id"] == current_user_id:
        can_delete = True

    if not can_delete:
        return {"message": "You don't have permission to delete this message!"}

    try:
        cursor.execute("DELETE FROM message WHERE id = %s", (message_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete message!"}

    return {"message": "Message deleted successfully"}


@conversations_blueprint.route('/messages/<int:message_id>/files', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "get_files"))
@jwt_required()
def get_files(message_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM message m
        JOIN participant p ON m.conversation_id = p.conversation_id
        WHERE m.id = %s AND p.user_id = %s
    """, (message_id, current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You don't have access to this message!"}

    cursor.execute("""
        SELECT id, message_id, name, extension FROM file WHERE message_id = %s
    """, (message_id,))
    files = cursor.fetchall()
    return {"message": "Success", "files": files}


@conversations_blueprint.route('/messages/<int:message_id>/files', methods=["POST"])
@swag_from(load_yaml("documentation/conversations.yaml", "upload_file"))
@jwt_required()
def upload_file(message_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT sender_id FROM message WHERE id = %s
    """, (message_id,))
    message = cursor.fetchone()

    if message is None:
        return {"message": "Message not found!"}
    if message["sender_id"] != current_user_id:
        return {"message": "You can only attach files to your own messages!"}

    try:
        content = request.files["content"]
        original_filename = content.filename
        name, extension = os.path.splitext(original_filename)
        extension = content.content_type.split('/')[-1]
        content = content.read()

        if not content:
            return {"message": "File is empty!"}
    except:
        return {"message": "Invalid format!"}

    try:
        cursor.execute("""
                INSERT INTO file (message_id, name, extension, content) 
                VALUES (%s, %s, %s, %s)
                RETURNING id
            """, (message_id, name, extension, content))

        file_id = cursor.fetchone()["id"]
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to upload file!"}

    return {
        "1": "File uploaded successfully",
        "file_id": file_id,
        "name": name,
        "extension": extension
    }


@conversations_blueprint.route('/files/<int:file_id>', methods=["GET"])
@swag_from(load_yaml("documentation/conversations.yaml", "download_file"))
@jwt_required()
def download_file(file_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT f.name, f.extension, f.content, m.conversation_id
        FROM file f
        JOIN message m ON f.message_id = m.id
        WHERE f.id = %s
    """, (file_id,))
    file_data = cursor.fetchone()

    if not file_data:
        return {"message": "File not found!"}

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (file_data["conversation_id"], current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You don't have access to this file!"}

    file_content = io.BytesIO(file_data["content"])
    filename = f"{file_data['name']}.{file_data['extension']}"

    return send_file(
        file_content,
        as_attachment=True,
        download_name=filename,
        mimetype='application/octet-stream'
    )


@conversations_blueprint.route('/files/<int:file_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/conversations.yaml", "delete_file"))
@jwt_required()
def delete_file(file_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT m.sender_id, m.conversation_id 
        FROM file f
        JOIN message m ON f.message_id = m.id
        JOIN conversation c ON m.conversation_id = c.id
        WHERE f.id = %s
    """, (file_id,))
    file_info = cursor.fetchone()

    if not file_info:
        return {"message": "File not found!"}

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (file_info["conversation_id"], current_user_id))
    if cursor.fetchone() is None:
        return {"message": "You don't have access to this conversation!"}

    can_delete = False

    if file_info["sender_id"] == current_user_id:
        can_delete = True

    if not can_delete:
        return {"message": "You don't have permission to delete this file!"}

    try:
        cursor.execute("DELETE FROM file WHERE id = %s", (file_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete file!"}

    return {"message": "File deleted successfully"}