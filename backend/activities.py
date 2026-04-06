from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, get_current_user_id, is_group_member, check_permission

activities_blueprint = Blueprint('activities', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)


def get_activity_info(activity_id):
    cursor.execute("SELECT group_id, creator_id FROM activity WHERE id_activity = %s", (activity_id,))
    return cursor.fetchone()

@activities_blueprint.route('/groups/<int:group_id>', methods=["GET"])
@jwt_required()
def get_activities(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "view_activities"):
        return {"message": "You don't have permission to view activities!"}, 403

    cursor.execute("""
        SELECT a.id_activity, a.name, a.description, a.creation_date, a.deadline,
               a.creator_id, u.username AS creator_username
        FROM activity a
        JOIN "user" u ON a.creator_id = u.id_registration
        WHERE a.group_id = %s
    """, (group_id,))
    activities = cursor.fetchall()
    return {"message": "Success", "activities": activities}, 200


@activities_blueprint.route('/groups/<int:group_id>', methods=["POST"])
@jwt_required()
def create_activity(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "create_activity"):
        return {"message": "You don't have permission to create activities!"}, 403

    try:
        name = request.json["name"]
        description = request.json.get("description")
        deadline = request.json.get("deadline")
    except:
        return {"message": "Invalid format!"}, 400

    try:
        cursor.execute("""
            INSERT INTO activity (name, description, deadline, creator_id, group_id)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id_activity
        """, (name, description, deadline, current_user_id, group_id))
        activity_id = cursor.fetchone()["id_activity"]
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to create activity!"}, 500

    return {"message": "Activity created successfully", "activity_id": activity_id}, 201


@activities_blueprint.route('/<int:activity_id>', methods=["GET"])
@jwt_required()
def get_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "view_activities"):
        return {"message": "You don't have permission to view activities!"}, 403

    cursor.execute("""
        SELECT a.id_activity, a.name, a.description, a.creation_date, a.deadline,
               a.creator_id, u.username AS creator_username
        FROM activity a
        JOIN "user" u ON a.creator_id = u.id_registration
        WHERE a.id_activity = %s
    """, (activity_id,))
    activity = cursor.fetchone()
    return {"message": "Success", "activity": activity}, 200


@activities_blueprint.route('/<int:activity_id>', methods=["PUT"])
@jwt_required()
def update_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]
    creator_id = info["creator_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    is_creator = (current_user_id == creator_id)
    if not is_creator and not check_permission(current_user_id, group_id, "edit_activity"):
        return {"message": "You don't have permission to edit this activity!"}, 403

    try:
        name = request.json.get("name")
        description = request.json.get("description")
        deadline = request.json.get("deadline")
    except:
        return {"message": "Invalid format!"}, 400

    try:
        cursor.execute("""
            UPDATE activity SET
                name = COALESCE(%s, name),
                description = COALESCE(%s, description),
                deadline = COALESCE(%s, deadline)
            WHERE id_activity = %s
        """, (name, description, deadline, activity_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to update activity!"}, 500

    return {"message": "Activity updated successfully"}, 200


@activities_blueprint.route('/<int:activity_id>', methods=["DELETE"])
@jwt_required()
def delete_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]
    creator_id = info["creator_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    is_creator = (current_user_id == creator_id)
    if not is_creator and not check_permission(current_user_id, group_id, "delete_activity"):
        return {"message": "You don't have permission to delete this activity!"}, 403

    try:
        cursor.execute("DELETE FROM activity WHERE id_activity = %s", (activity_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete activity!"}, 500

    return {"message": "Activity deleted successfully"}, 200


@activities_blueprint.route('/<int:activity_id>/users', methods=["GET"])
@jwt_required()
def get_activity_users(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    cursor.execute("""
        SELECT u.id_registration, u.username, us.name, us.surname
        FROM activity_user au
        JOIN "user" u ON au.id_user = u.id_registration
        JOIN user_setting us ON u.id_user_settings = us.id_user_setting
        WHERE au.id_activity = %s
    """, (activity_id,))
    users = cursor.fetchall()
    return {"message": "Success", "users": users}, 200


@activities_blueprint.route('/<int:activity_id>/users', methods=["POST"])
@jwt_required()
def assign_activity_user(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "assign_activity_user"):
        return {"message": "You don't have permission to assign users to activities!"}, 403

    try:
        user_id = request.json["user_id"]
    except:
        return {"message": "Invalid format!"}, 400

    try:
        cursor.execute("""
            INSERT INTO activity_user (id_user, id_activity) VALUES (%s, %s)
        """, (user_id, activity_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to assign user to activity!"}, 500

    return {"message": "User assigned to activity successfully"}, 200


@activities_blueprint.route('/<int:activity_id>/users/<int:user_id>', methods=["DELETE"])
@jwt_required()
def remove_activity_user(activity_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "assign_activity_user"):
        return {"message": "You don't have permission to remove users from activities!"}, 403

    try:
        cursor.execute("""
            DELETE FROM activity_user WHERE id_user = %s AND id_activity = %s
        """, (user_id, activity_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to remove user from activity!"}, 500

    return {"message": "User removed from activity successfully"}, 200