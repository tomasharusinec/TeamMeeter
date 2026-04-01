from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, get_current_user_id

conversations_blueprint = Blueprint('/conversations', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@conversations_blueprint.route('/', methods=["GET"])
@jwt_required()
def get_conversations():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT c.id, c.name, c.created_at, c.type
        FROM conversation c
        JOIN participant p ON c.id = p.conversation_id
        WHERE p.user_id = %s
    """, (current_user_id,))
    conversations = cursor.fetchall()
    return {"1": "Success", "conversations": conversations}


@conversations_blueprint.route('/', methods=["POST"])
@jwt_required()
def create_conversation():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    try:
        name = request.json.get("name")
        conv_type = request.json["type"]
        participant_ids = request.json.get("participant_ids", [])
    except:
        return {"-1": "Invalid format!"}

    if conv_type not in ("individual", "group"):
        return {"-1": "Type must be 'individual' or 'group'!"}

    try:
        cursor.execute("""
            INSERT INTO conversation (name, type) VALUES (%s, %s)
            RETURNING id
        """, (name, conv_type))
        conv_id = cursor.fetchone()["id"]

        cursor.execute("""
            INSERT INTO participant (conversation_id, user_id) VALUES (%s, %s)
        """, (conv_id, current_user_id))

        for pid in participant_ids:
            if pid != current_user_id:
                cursor.execute("""
                    INSERT INTO participant (conversation_id, user_id) VALUES (%s, %s)
                """, (conv_id, pid))

        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to create conversation!"}

    return {"1": "Conversation created successfully", "conversation_id": conv_id}


@conversations_blueprint.route('/<int:conv_id>', methods=["GET"])
@jwt_required()
def get_conversation(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"-1": "You are not a participant of this conversation!"}

    cursor.execute("""
        SELECT id, name, created_at, type FROM conversation WHERE id = %s
    """, (conv_id,))
    conversation = cursor.fetchone()
    if conversation is None:
        return {"-1": "Conversation not found!"}
    return {"1": "Success", "conversation": conversation}


@conversations_blueprint.route('/<int:conv_id>', methods=["DELETE"])
@jwt_required()
def delete_conversation(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"-1": "You are not a participant of this conversation!"}

    try:
        cursor.execute("DELETE FROM conversation WHERE id = %s", (conv_id,))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to delete conversation!"}

    return {"1": "Conversation deleted successfully"}


@conversations_blueprint.route('/<int:conv_id>/participants', methods=["GET"])
@jwt_required()
def get_participants(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"-1": "You are not a participant of this conversation!"}

    cursor.execute("""
        SELECT u.id_registration, u.username, us.name, us.surname
        FROM participant p
        JOIN "user" u ON p.user_id = u.id_registration
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE p.conversation_id = %s
    """, (conv_id,))
    participants = cursor.fetchall()
    return {"1": "Success", "participants": participants}


@conversations_blueprint.route('/<int:conv_id>/participants', methods=["POST"])
@jwt_required()
def add_participant(conv_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"-1": "You are not a participant of this conversation!"}

    try:
        user_id = request.json["user_id"]
    except:
        return {"-1": "Invalid format!"}

    try:
        cursor.execute("""
            INSERT INTO participant (conversation_id, user_id) VALUES (%s, %s)
        """, (conv_id, user_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to add participant!"}

    return {"1": "Participant added successfully"}


@conversations_blueprint.route('/<int:conv_id>/participants/<int:user_id>', methods=["DELETE"])
@jwt_required()
def remove_participant(conv_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT 1 FROM participant WHERE conversation_id = %s AND user_id = %s
    """, (conv_id, current_user_id))
    if cursor.fetchone() is None:
        return {"-1": "You are not a participant of this conversation!"}

    try:
        cursor.execute("""
            DELETE FROM participant WHERE conversation_id = %s AND user_id = %s
        """, (conv_id, user_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to remove participant!"}

    return {"1": "Participant removed successfully"}