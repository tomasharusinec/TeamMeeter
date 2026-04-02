from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, is_group_member, check_permission

roles_blueprint = Blueprint('/roles', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@roles_blueprint.route('/groups/<int:group_id>', methods=["GET"])
@jwt_required()
def get_roles(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    cursor.execute("""
        SELECT id_role, name, color FROM role WHERE group_id = %s
    """, (group_id,))
    roles = cursor.fetchall()
    return {"1": "Success", "roles": roles}


@roles_blueprint.route('/groups/<int:group_id>', methods=["POST"])
@jwt_required()
def create_role(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "create_role"):
        return {"-1": "You don't have permission to create role!"}

    try:
        name = request.json["name"]
        color = request.json.get("color")
        permissions_list = request.json.get("permissions", [])
    except:
        return {"-1": "Invalid format!"}

    try:
        cursor.execute("""INSERT INTO role (group_id, name, color) 
                          VALUES (%s, %s, %s)
            RETURNING id_role
        """, (group_id, name, color))
        role_id = cursor.fetchone()["id_role"]

        if permissions_list:
            cursor.execute("""INSERT INTO Role_permission (role_id, permission_id, value) 
                              SELECT %s, id_permission, TRUE 
                              FROM Permission 
                              WHERE name = ANY (%s) 
                            """, (role_id, permissions_list))
        db.commit()

    except:
        db.rollback()
        return {"-2": "Failed to create role!"}

    return {"1": "Role created successfully", "role_id": role_id, "assigned_permissions": permissions_list}


@roles_blueprint.route('/groups/<int:group_id>/<int:role_id>', methods=["PUT"])
@jwt_required()
def update_role(group_id, role_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "edit_role"):
        return {"-1": "You don't have permission to manage roles!"}

    try:
        name = request.json.get("name")
        color = request.json.get("color")

    except:
        return {"-1": "Invalid format!"}

    permissions_list = request.json.get("permissions")

    try:
        cursor.execute("""
            UPDATE role SET
                name = COALESCE(%s, name),
                color = COALESCE(%s, color)
            WHERE id_role = %s AND group_id = %s
        """, (name, color, role_id, group_id))

        if permissions_list is not None:

            cursor.execute("DELETE FROM Role_permission WHERE role_id = %s", (role_id,))

            if permissions_list:
                cursor.execute("""
                               INSERT INTO Role_permission (role_id, permission_id, value)
                               SELECT %s, id_permission, TRUE
                               FROM Permission
                               WHERE name = ANY (%s)
                               """, (role_id, permissions_list))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to update role!"}

    return {"1": "Role updated successfully"}


@roles_blueprint.route('/groups/<int:group_id>/roles/<int:role_id>', methods=["DELETE"])
@jwt_required()
def delete_role(group_id, role_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "delete_role"):
        return {"-1": "You don't have permission to manage roles!"}

    try:
        cursor.execute("""
            DELETE FROM role WHERE id_role = %s AND group_id = %s
        """, (role_id, group_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to delete role!"}

    return {"1": "Role deleted successfully"}




@roles_blueprint.route('/groups/<int:group_id>/users/<int:user_id>', methods=["GET"])
@jwt_required()
def get_user_roles(group_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    cursor.execute("""
        SELECT r.id_role, r.name, r.color
        FROM user_role ur
        JOIN role r ON ur.role_id = r.id_role
        WHERE ur.user_id = %s AND r.group_id = %s
    """, (user_id, group_id))
    roles = cursor.fetchall()
    return {"1": "Success", "roles": roles}


@roles_blueprint.route('/groups/<int:group_id>/assign', methods=["POST"])
@jwt_required()
def assign_user_role(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "add_role"):
        return {"-1": "You don't have permission to manage roles!"}

    try:
        username = request.json["username"]
        role_id = request.json["role_id"]
    except:
        return {"-1": "Invalid format!"}


    cursor.execute("SELECT id_role FROM role WHERE id_role = %s AND group_id = %s", (role_id, group_id))
    if cursor.fetchone() is None:
        return {"-1": "Role not found in this group!"}

    try:

        cursor.execute("""SELECT u.id_registration 
                          FROM "user" u 
                        JOIN Group_member gm ON u.id_registration = gm.user_id
                        WHERE u.username = %s
                        AND gm.group_id = %s
                        """, (username, group_id))

        user_row = cursor.fetchone()
        if not user_row:
            return {"-1": "User not found or is not a member of this group!"}

        user_id = user_row["id_registration"]
        cursor.execute("""
            INSERT INTO user_role (user_id, role_id) VALUES (%s, %s)
        """, (user_id, role_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to assign role!"}

    return {"1": "Role assigned successfully"}


@roles_blueprint.route('/groups/<int:group_id>/users/<int:user_id>/roles/<int:role_id>', methods=["DELETE"])
@jwt_required()
def remove_user_role(group_id, user_id, role_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "manage_roles"):
        return {"-1": "You don't have permission to manage roles!"}

    try:
        cursor.execute("""
            DELETE FROM user_role WHERE user_id = %s AND role_id = %s
        """, (user_id, role_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to remove role!"}

    return {"1": "Role removed successfully"}


