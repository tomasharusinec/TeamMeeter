from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, is_group_member, check_permission
from flasgger import Swagger, swag_from


groups_blueprint = Blueprint('groups', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@groups_blueprint.route('/', methods = ['POST'])
@jwt_required()
def create_group():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    name = request.json.get("name")
    icon = request.json.get("icon", "default_icon.png")

    if not name:
        return {"-1": "Group name is required!"}

    try:
        with db.cursor() as cursor:
            cursor.execute("""INSERT INTO "group" (name, icon)
                              VALUES (%s, %s) RETURNING id_group""", (name, icon))
            new_group_id = cursor.fetchone()[0]

            cursor.execute("""INSERT INTO role (group_id, name, color)
                              VALUES (%s, 'Manager', '#FF0000') RETURNING id_role""", (new_group_id,))
            role_id = cursor.fetchone()[0]

            cursor.execute("""INSERT INTO role_permission (role_id, permission_id, value)
                                    SELECT %s, id_permission, TRUE
                                    FROM permission""", (role_id,))

            cursor.execute("""INSERT INTO group_member (group_id, user_id)
                              VALUES (%s, %s)""", (new_group_id, user_id))

            cursor.execute("""INSERT INTO user_role (user_id, role_id)
                              VALUES (%s, %s)""", (user_id, role_id))

            db.commit()
            return {"1": "Group created successfully", "group_id": new_group_id}
    except:
        db.rollback()
        return {"-1": "error"}

@groups_blueprint.route('/', methods=["GET"])
@jwt_required()
def get_groups():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
        SELECT g.id_group, g.name, g.create_date, g.icon
        FROM "group" g
        JOIN group_member gm ON g.id_group = gm.group_id
        WHERE gm.user_id = %s
    """, (current_user_id,))
    groups = cursor.fetchall()
    return {"1": "Success", "groups": groups}


@groups_blueprint.route('/<int:group_id>', methods=["GET"])
@jwt_required()
def get_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    cursor.execute("""
        SELECT id_group, name, create_date, icon FROM "group" WHERE id_group = %s
    """, (group_id,))
    group = cursor.fetchone()
    if group is None:
        return {"-1": "Group not found!"}
    return {"1": "Success", "group": group}


@groups_blueprint.route('/<int:group_id>', methods=["PUT"])
@jwt_required()
def update_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {"-1": "You don't have permission to manage this group!"}

    try:
        name = request.json.get("name")
        icon = request.json.get("icon")
    except:
        return {"-1": "Invalid format!"}

    try:
        cursor.execute("""
            UPDATE "group" SET
                name = COALESCE(%s, name),
                icon = COALESCE(%s, icon)
            WHERE id_group = %s
        """, (name, icon, group_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to update group!"}

    return {"1": "Group updated successfully"}


@groups_blueprint.route('/<int:group_id>', methods=["DELETE"])
@jwt_required()
def delete_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "delete_group"):
        return {"-1": "You don't have permission to delete this group!"}

    try:
        cursor.execute('DELETE FROM "group" WHERE id_group = %s', (group_id,))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to delete group!"}

    return {"1": "Group deleted successfully"}

@groups_blueprint.route('/<int:group_id>/members', methods=["GET"])
@jwt_required()
def get_group_members(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    cursor.execute("""
        SELECT u.id_registration, u.username, u.email,
               us.name, us.surname, us.profile_picture
        FROM group_member gm
        JOIN "user" u ON gm.user_id = u.id_registration
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE gm.group_id = %s
    """, (group_id,))
    members = cursor.fetchall()
    print(members)
    return {"1": "Success", "members": members}


@groups_blueprint.route('/<int:group_id>/members', methods=["POST"])
@jwt_required()
def add_group_member(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "add_user"):
        return {"-1": "You don't have permission to add users!"}

    try:
        username = request.json["username"]
    except:
        return {"-1": "Invalid format!"}

    cursor.execute("""SELECT id_registration FROM "user" 
                            WHERE username = %s""", (username, ))
    result = cursor.fetchone()

    if not result:
        return {"-1": "User not found"}

    user_id = result["id_registration"]
    cursor.execute('SELECT id_registration FROM "user" WHERE id_registration = %s', (user_id,))
    if cursor.fetchone() is None:
        return {"-1": "User not found!"}

    if is_group_member(user_id, group_id):
        return {"-1": "User is already a member of this group!"}

    try:
        cursor.execute("""INSERT INTO group_member (group_id, user_id) 
                            VALUES (%s, %s)
                                """, (group_id, user_id))
        cursor.execute('SELECT id_role FROM role WHERE group_id = %s AND name = %s', (group_id, 'Member'))
        role_result = cursor.fetchone()

        if role_result:
            role_id = role_result["id_role"]
        else:
            # Ak rola Member neexistuje, vytvoríme ju
            cursor.execute('INSERT INTO role (group_id, name, color) VALUES (%s, %s, %s) RETURNING id_role',
                           (group_id, 'Member', '#808080'))
            role_id = cursor.fetchone()["id_role"]

            # Priradíme tejto novej role všetky existujúce práva, ale nastavené na FALSE
            cursor.execute("""INSERT INTO role_permission (role_id, permission_id, value)
                            SELECT %s, id_permission, FALSE
                            FROM permission
                            """, (role_id,))

        # 8. Priradenie roly používateľovi
        cursor.execute('INSERT INTO user_role (user_id, role_id) VALUES (%s, %s)', (user_id, role_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to add member!"}

    return {"1": "Member added successfully"}


@groups_blueprint.route('/<int:group_id>/members/<int:user_id>', methods=["DELETE"])
@jwt_required()
def remove_group_member(group_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"-1": "You are not a member of this group!"}

    if not check_permission(current_user_id, group_id, "kick_user"):
        return {"-1": "You don't have permission to manage members!"}

    try:
        cursor.execute("""
            DELETE FROM group_member WHERE group_id = %s AND user_id = %s
        """, (group_id, user_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to remove member!"}

    return {"1": "Member removed successfully"}