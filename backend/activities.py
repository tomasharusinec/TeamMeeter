from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from datetime import datetime
from websocket_handler import create_activity_notification, get_db_connection
from helper_func import db, get_current_user_id, is_group_member, check_permission, load_yaml, parse_client_deadline

activities_blueprint = Blueprint('activities', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

# Gets basic activity info (group_id and creator_id).
def get_activity_info(activity_id):
    cursor.execute("SELECT group_id, creator_id FROM activity WHERE id_activity = %s", (activity_id,))
    return cursor.fetchone()

@activities_blueprint.route('/individual', methods=["POST"])
@swag_from(load_yaml("documentation/activities.yaml", "create_individual_activity"))
@jwt_required()
# Creates a new individual activity.
def create_individual_activity():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    try:
        name = request.json["name"]
        description = request.json.get("description")
        deadline_str = request.json.get("deadline")
    except:
        return {"message": "Invalid format!"}, 400

    deadline_date = None
    if deadline_str:
        try:
            deadline_date = parse_client_deadline(deadline_str)
            if deadline_date < datetime.now(deadline_date.tzinfo):
                return {"message": "This date is invalid!"}, 400
        except ValueError:
            return {"message": "Invalid date format!"}, 400

    try:
        cursor.execute("""
            INSERT INTO activity (name, description, deadline, status, creator_id, group_id)
            VALUES (%s, %s, %s, 'todo', %s, NULL)
            RETURNING id_activity
        """, (name, description, deadline_date, current_user_id))
        activity_id = cursor.fetchone()["id_activity"]
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to create activity!"}, 500

    return {"message": "Activity created successfully", "activity_id": activity_id}, 201


@activities_blueprint.route('/groups/<int:group_id>', methods=["GET"])
@swag_from(load_yaml("documentation/activities.yaml", "get_activities"))
@jwt_required()
# Gets all activities for a group. Requires membership and 'view_activities' permission.
def get_activities(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "view_activities"):
        return {"message": "You don't have permission to view activities!"}, 403

    cursor.execute("""
        SELECT a.id_activity, a.name, a.description, a.creation_date, a.deadline, a.status, a.creator_id, u.username AS creator_username
        FROM activity a
        JOIN "user" u ON a.creator_id = u.id_registration
        WHERE a.group_id = %s
    """, (group_id,))
    activities = cursor.fetchall()
    return {"message": "Success", "activities": activities}, 200


@activities_blueprint.route('/groups/<int:group_id>', methods=["POST"])
@swag_from(load_yaml("documentation/activities.yaml", "create_activity"))
@jwt_required()
# Creates a new group activity and notifies members. Requires membership and 'create_activity' permission.
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
        deadline_str = request.json.get("deadline")
    except:
        return {"message": "Invalid format!"}, 400

    deadline_date = None
    if deadline_str:
        try:
            deadline_date = parse_client_deadline(deadline_str)
            if deadline_date < datetime.now(deadline_date.tzinfo):
                return {"message": "This date is invalid!"}, 400
        except ValueError:
            return {"message": "Invalid date format!"}, 400

    try:
        cursor.execute("""
            INSERT INTO activity (name, description, deadline, status, creator_id, group_id)
            VALUES (%s, %s, %s, 'todo', %s, %s)
            RETURNING id_activity
        """, (name, description, deadline_date, current_user_id, group_id))
        activity_id = cursor.fetchone()["id_activity"]
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to create activity!"}, 500

    try:
        ws_conn = get_db_connection()
        try:
            create_activity_notification(ws_conn, activity_id, group_id, current_user_id, name)
        finally:
            ws_conn.close()
    except:
        pass

    return {"message": "Activity created successfully", "activity_id": activity_id}, 201


@activities_blueprint.route('/<int:activity_id>', methods=["GET"])
@swag_from(load_yaml("documentation/activities.yaml", "get_activity"))
@jwt_required()
# Gets details of a specific activity. Requires access (group member or creator).
def get_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        if info["creator_id"] != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

        if not check_permission(current_user_id, group_id, "view_activities"):
            return {"message": "You don't have permission to view activities!"}, 403

    cursor.execute("""
        SELECT a.id_activity, a.name, a.description, a.creation_date, a.deadline, a.status, a.creator_id, a.group_id, u.username AS creator_username
        FROM activity a
        JOIN "user" u ON a.creator_id = u.id_registration
        WHERE a.id_activity = %s
    """, (activity_id,))
    activity = cursor.fetchone()
    return {"message": "Success", "activity": activity}, 200


@activities_blueprint.route('/<int:activity_id>', methods=["PUT"])
@swag_from(load_yaml("documentation/activities.yaml", "update_activity"))
@jwt_required()
# Updates activity details. Requires being creator or having 'edit_activity' permission.
def update_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]
    creator_id = info["creator_id"]

    if group_id is None:
        if creator_id != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

        is_creator = (current_user_id == creator_id)
        if not is_creator:
            # Drag/drop + "mark as done" send only status in PUT body.
            # In that case, allow status updates for assigned users/roles
            # even without edit_activity permission.
            try:
                name_tmp = request.json.get("name")
                description_tmp = request.json.get("description")
                deadline_str_tmp = request.json.get("deadline")
                status_tmp = request.json.get("status")
                is_status_only_update = (
                    status_tmp is not None
                    and name_tmp is None
                    and description_tmp is None
                    and deadline_str_tmp is None
                )
            except Exception:
                is_status_only_update = False

            if is_status_only_update:
                cursor.execute(
                    """
                    SELECT 1
                    FROM activity_user au
                    WHERE au.id_activity = %s AND au.id_user = %s
                    LIMIT 1
                    """,
                    (activity_id, current_user_id),
                )
                assigned_by_user = cursor.fetchone() is not None

                assigned_by_role = False
                if not assigned_by_user:
                    cursor.execute(
                        """
                        SELECT 1
                        FROM activity_role ar
                        JOIN user_role ur ON ar.role_id = ur.role_id
                        WHERE ar.activity_id = %s AND ur.user_id = %s
                        LIMIT 1
                        """,
                        (activity_id, current_user_id),
                    )
                    assigned_by_role = cursor.fetchone() is not None

                if not (assigned_by_user or assigned_by_role):
                    return {"message": "You don't have permission to update this activity status!"}, 403
            else:
                if not check_permission(current_user_id, group_id, "edit_activity"):
                    return {"message": "You don't have permission to edit this activity!"}, 403

    try:
        name = request.json.get("name")
        description = request.json.get("description")
        deadline_str = request.json.get("deadline")
        status = request.json.get("status")
    except:
        return {"message": "Invalid format!"}, 400

    allowed_statuses = {'todo', 'in_progress', 'completed'}
    if status is not None:
        if str(status) not in allowed_statuses:
            return {"message": "Invalid status!"}, 400
        status = str(status)
    else:
        status = None

    deadline_date = None
    if deadline_str:
        try:
            deadline_date = parse_client_deadline(deadline_str)
            if deadline_date < datetime.now(deadline_date.tzinfo):
                return {"message": "This date is invalid!"}, 400
        except ValueError:
            return {"message": "Invalid date format!"}, 400

    try:
        cursor.execute("""
            UPDATE activity SET
                name = COALESCE(%s, name),
                description = COALESCE(%s, description),
                deadline = COALESCE(%s, deadline),
                status = COALESCE(%s, status)
            WHERE id_activity = %s
        """, (name, description, deadline_date, status, activity_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to update activity!"}, 500

    return {"message": "Activity updated successfully"}, 200


@activities_blueprint.route('/<int:activity_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/activities.yaml", "delete_activity"))
@jwt_required()
# Deletes an activity. Requires being creator or having 'delete_activity' permission.
def delete_activity(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]
    creator_id = info["creator_id"]

    if group_id is None:
        if creator_id != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
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


# Lists users assigned to an activity. Requires activity access.
@activities_blueprint.route('/<int:activity_id>/users', methods=["GET"])
@swag_from(load_yaml("documentation/activities.yaml", "get_activity_users"))
@jwt_required()
# Lists users assigned to an activity. Requires activity access.
def get_activity_users(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        cursor.execute("SELECT 1 FROM activity_user WHERE id_activity = %s AND id_user = %s", (activity_id, current_user_id))
        is_assigned = cursor.fetchone() is not None
        if info["creator_id"] != current_user_id and not is_assigned:
            return {"message": "You don't have access to this activity!"}, 403
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

    # Query below was generated using AI (Gemini)
    cursor.execute("""
            SELECT u.id_registration, u.username, us.name, us.surname
            FROM activity_user au
            JOIN "user" u ON au.id_user = u.id_registration
            JOIN user_setting us ON u.id_registration = us.id_user
            WHERE au.id_activity = %s
            UNION
            SELECT u.id_registration, u.username, us.name, us.surname
            FROM activity_role ar
            JOIN user_role ur ON ar.role_id = ur.role_id
            JOIN "user" u ON ur.user_id = u.id_registration
            JOIN user_setting us ON u.id_registration = us.id_user
            WHERE ar.activity_id = %s
            UNION
            SELECT u.id_registration, u.username, us.name, us.surname
            FROM activity a
            JOIN "user" u ON a.creator_id = u.id_registration
            JOIN user_setting us ON u.id_registration = us.id_user
            WHERE a.id_activity = %s AND a.group_id IS NULL
        """, (activity_id, activity_id, activity_id))
    users = cursor.fetchall()
    return {"message": "Success", "users": users}, 200


@activities_blueprint.route('/<int:activity_id>/users', methods=["POST"])
@swag_from(load_yaml("documentation/activities.yaml", "assign_activity_user"))
@jwt_required()
# Assigns a user to an activity. Requires 'assign_activity_user' permission.
def assign_activity_user(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        if info["creator_id"] != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
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
@swag_from(load_yaml("documentation/activities.yaml", "remove_activity_user"))
@jwt_required()
# Removes a user assignment from an activity. Requires 'assign_activity_user' permission.
def remove_activity_user(activity_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        if info["creator_id"] != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
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

@activities_blueprint.route('/<int:activity_id>/roles', methods=["GET"])
@swag_from(load_yaml("documentation/activities.yaml", "get_activity_roles"))
@jwt_required()
# Lists roles assigned to an activity. Requires activity access.
def get_activity_roles(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        if info["creator_id"] != current_user_id:
            return {"message": "You don't have access to this activity!"}, 403
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

    cursor.execute("""
        SELECT r.id_role, r.name, r.color
        FROM activity_role ar
        JOIN role r ON ar.role_id = r.id_role
        WHERE ar.activity_id = %s
    """, (activity_id,))
    roles = cursor.fetchall()
    return {"message": "Success", "roles": roles}, 200


@activities_blueprint.route('/<int:activity_id>/roles', methods=["POST"])
@swag_from(load_yaml("documentation/activities.yaml", "assign_activity_role"))
@jwt_required()
# This function was edited using AI (Gemini)
# Assigns a role to an activity. Requires 'assign_activity_role' permission.
def assign_activity_role(activity_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        return {"message": "Cannot assign roles to individual activities!"}, 400
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

        if not check_permission(current_user_id, group_id, "assign_activity_role"):
            return {"message": "You don't have permission to assign roles to activities!"}, 403

    try:
        role_id = request.json["role_id"]
    except:
        return {"message": "Invalid format!"}, 400

    cursor.execute("""
            SELECT 1 FROM role 
            WHERE id_role = %s AND group_id = %s
        """, (role_id, group_id))

    if cursor.fetchone() is None:
        return {"message": "Role does not belong to this group!"}, 400

    try:
        cursor.execute("""
            INSERT INTO activity_role (activity_id, role_id) VALUES (%s, %s)
        """, (activity_id, role_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to assign role to activity!"}, 500

    return {"message": "Role assigned to activity successfully"}, 200


@activities_blueprint.route('/<int:activity_id>/roles/<int:role_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/activities.yaml", "remove_activity_role"))
@jwt_required()
# Removes a role assignment from an activity. Requires 'assign_activity_role' permission.
def remove_activity_role(activity_id, role_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    info = get_activity_info(activity_id)
    if info is None:
        return {"message": "Activity not found!"}, 404

    group_id = info["group_id"]

    if group_id is None:
        return {"message": "Cannot remove roles from individual activities!"}, 400
    else:
        if not is_group_member(current_user_id, group_id):
            return {"message": "You are not a member of this group!"}, 403

        if not check_permission(current_user_id, group_id, "assign_activity_role"):
            return {"message": "You don't have permission to remove roles from activities!"}, 403

    try:
        cursor.execute("""
            DELETE FROM activity_role WHERE activity_id = %s AND role_id = %s
        """, (activity_id, role_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to remove role from activity!"}, 500

    return {"message": "Role removed from activity successfully"}, 200


@activities_blueprint.route('/me', methods=["GET"])
@swag_from(load_yaml("documentation/activities.yaml", "get_my_activities"))
@jwt_required()
# Function below was generated using AI (Gemini)
# Lists all activities relevant to the authenticated user.
def get_my_activities():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT DISTINCT a.id_activity, a.name, a.description, a.creation_date, a.deadline, a.status, a.group_id, g.name AS group_name, u_creator.username AS creator_username
        FROM activity a
        LEFT JOIN "group" g ON a.group_id = g.id_group
        JOIN "user" u_creator ON a.creator_id = u_creator.id_registration
        LEFT JOIN activity_user au ON a.id_activity = au.id_activity
        LEFT JOIN activity_role ar ON a.id_activity = ar.activity_id
        LEFT JOIN user_role ur ON ar.role_id = ur.role_id AND ur.user_id = %s
        WHERE au.id_user = %s OR ur.user_id = %s OR (a.group_id IS NULL AND a.creator_id = %s)
    """, (current_user_id, current_user_id, current_user_id, current_user_id))
    activities = cursor.fetchall()

    return {"message": "Success", "activities": activities}, 200