from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, is_group_member, check_permission, load_yaml

groups_blueprint = Blueprint('groups', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@groups_blueprint.route('/', methods=['POST'])
@swag_from(load_yaml("documentation/groups.yaml", "create_group"))
@jwt_required()
def create_group():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    name = request.json.get("name")
    icon = request.json.get("icon", "default_icon.png")

    if not name:
        return {
            "message": "Group name is required!"
        }, 400

    try:
        with db.cursor(cursor_factory=RealDictCursor) as cursor:

            cursor.execute("""
                           INSERT INTO conversation (name)
                           VALUES (%s) RETURNING id
                           """, (name,))
            conv_id = cursor.fetchone()["id"]

            cursor.execute("""
                           INSERT INTO participant (conversation_id, user_id)
                           VALUES (%s, %s)
                           """, (conv_id, user_id))

            cursor.execute("""INSERT INTO "group" (name, icon, conversation_id)
                              VALUES (%s, %s, %s) RETURNING id_group""", (name, icon, conv_id))
            new_group_id = cursor.fetchone()["id_group"]

            cursor.execute("""INSERT INTO role (group_id, name, color)
                              VALUES (%s, 'Manager', '#FF0000') RETURNING id_role""", (new_group_id,))
            role_id = cursor.fetchone()["id_role"]

            cursor.execute("""INSERT INTO role_permission (role_id, permission_id, value)
                              SELECT %s, id_permission, TRUE
                              FROM permission""", (role_id,))

            cursor.execute("""INSERT INTO group_member (group_id, user_id)
                              VALUES (%s, %s)""", (new_group_id, user_id))

            cursor.execute("""INSERT INTO user_role (user_id, role_id)
                              VALUES (%s, %s)""", (user_id, role_id))

            db.commit()
            return {
                "message": "Group created successfully",
                "group_id": new_group_id,
                "conversation_id": conv_id
            }, 201
    except Exception as e:
        db.rollback()
        return {
            "message": "error"
        }, 500


@groups_blueprint.route('/', methods=["GET"])
@swag_from(load_yaml("documentation/groups.yaml", "get_groups"))
@jwt_required()
def get_groups():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
                   SELECT g.name, g.icon
                   FROM "group" g
                            JOIN group_member gm ON g.id_group = gm.group_id
                   WHERE gm.user_id = %s
                   """, (current_user_id,))
    groups = cursor.fetchall()
    return {
        "message": "Success",
        "groups": groups
    }, 200


@groups_blueprint.route('/<int:group_id>', methods=["GET"])
@swag_from(load_yaml("documentation/groups.yaml", "get_group"))
@jwt_required()
def get_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    cursor.execute("""
                   SELECT id_group, name, create_date, icon, conversation_id
                   FROM "group"
                   WHERE id_group = %s
                   """, (group_id,))
    group = cursor.fetchone()
    if group is None:
        return {
            "message": "Group not found!"
        }, 404
    return {
        "message": "Success",
        "group": group
    }, 200


@groups_blueprint.route('/<int:group_id>', methods=["PUT"])
@swag_from(load_yaml("documentation/groups.yaml", "update_group"))
@jwt_required()
def update_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {
            "message": "You don't have permission to manage this group!"
        }, 403

    try:
        name = request.json.get("name")
        icon = request.json.get("icon")
    except:
        return {
            "message": "Invalid format!"
        }, 400

    try:
        cursor.execute("""
                       UPDATE "group"
                       SET name = COALESCE(%s, name),
                           icon = COALESCE(%s, icon)
                       WHERE id_group = %s RETURNING conversation_id
                       """, (name, icon, group_id))

        updated_group = cursor.fetchone()

        # Ak sa zmenilo meno skupiny, synchronizujeme aj meno konverzácie
        if name and updated_group and updated_group["conversation_id"]:
            cursor.execute("""
                           UPDATE conversation
                           SET name = %s
                           WHERE id = %s
                           """, (name, updated_group["conversation_id"]))

        db.commit()
    except:
        db.rollback()
        return {
            "message": "Failed to update group!"
        }, 500

    return {
        "message": "Group updated successfully"
    }, 200


@groups_blueprint.route('/<int:group_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/groups.yaml", "delete_group"))
@jwt_required()
def delete_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    if not check_permission(current_user_id, group_id, "delete_group"):
        return {
            "message": "You don't have permission to delete this group!"
        }, 403

    try:
        cursor.execute('SELECT conversation_id FROM "group" WHERE id_group = %s', (group_id,))
        conv_data = cursor.fetchone()

        cursor.execute('DELETE FROM "group" WHERE id_group = %s', (group_id,))

        # Zmazanie priradenej konverzácie (a kaskádovo aj jej účastníkov)
        if conv_data and conv_data["conversation_id"]:
            conv_id = conv_data["conversation_id"]
            cursor.execute('DELETE FROM participant WHERE conversation_id = %s', (conv_id,))
            cursor.execute('DELETE FROM conversation WHERE id = %s', (conv_id,))

        db.commit()
    except:
        db.rollback()
        return {
            "message": "Failed to delete group!"
        }, 500

    return {
        "message": "Group deleted successfully"
    }, 200


@groups_blueprint.route('/<int:group_id>/members', methods=["GET"])
@swag_from(load_yaml("documentation/groups.yaml", "get_group_members"))
@jwt_required()
def get_group_members(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    cursor.execute("""
                   SELECT u.id_registration,
                          u.username,
                          u.email,
                          us.name,
                          us.surname,
                          us.profile_picture
                   FROM group_member gm
                            JOIN "user" u ON gm.user_id = u.id_registration
                            JOIN user_setting us ON u.id_registration = us.id_user
                   WHERE gm.group_id = %s
                   """, (group_id,))
    members = cursor.fetchall()
    return {
        "message": "Success",
        "members": members
    }, 200


@groups_blueprint.route('/<int:group_id>/members', methods=["POST"])
@swag_from(load_yaml("documentation/groups.yaml", "add_group_member"))
@jwt_required()
def add_group_member(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    if not check_permission(current_user_id, group_id, "add_user"):
        return {
            "message": "You don't have permission to add users!"
        }, 403

    try:
        username = request.json["username"]
    except:
        return {
            "message": "Invalid format!"
        }, 400

    cursor.execute("""SELECT id_registration
                      FROM "user"
                      WHERE username = %s""", (username,))
    result = cursor.fetchone()

    if not result:
        return {
            "message": "User not found!"
        }, 404

    user_id = result["id_registration"]
    cursor.execute('SELECT id_registration FROM "user" WHERE id_registration = %s', (user_id,))
    if cursor.fetchone() is None:
        return {
            "message": "User not found!"
        }, 404

    if is_group_member(user_id, group_id):
        return {
            "message": "User is already a member of this group!"
        }, 400

    try:
        cursor.execute("""INSERT INTO group_member (group_id, user_id)
                          VALUES (%s, %s)
                       """, (group_id, user_id))
        cursor.execute('SELECT id_role FROM role WHERE group_id = %s AND name = %s', (group_id, 'Member'))
        role_result = cursor.fetchone()

        if role_result:
            role_id = role_result["id_role"]
        else:
            cursor.execute('INSERT INTO role (group_id, name, color) VALUES (%s, %s, %s) RETURNING id_role',
                           (group_id, 'Member', '#808080'))
            role_id = cursor.fetchone()["id_role"]

            cursor.execute("""INSERT INTO role_permission (role_id, permission_id, value)
                              SELECT %s, id_permission, FALSE
                              FROM permission
                           """, (role_id,))

        cursor.execute('INSERT INTO user_role (user_id, role_id) VALUES (%s, %s)', (user_id, role_id))

        # Pridanie používateľa do konverzácie skupiny
        cursor.execute('SELECT conversation_id FROM "group" WHERE id_group = %s', (group_id,))
        conv_data = cursor.fetchone()
        if conv_data and conv_data["conversation_id"]:
            cursor.execute("""
                           INSERT INTO participant (conversation_id, user_id)
                           VALUES (%s, %s)
                           """, (conv_data["conversation_id"], user_id))

        db.commit()
    except Exception as e:
        print(e)
        db.rollback()
        return {
            "message": "Failed to add member!"
        }, 500

    return {
        "message": "Member added successfully"
    }, 200


@groups_blueprint.route('/<int:group_id>/members/<int:user_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/groups.yaml", "remove_group_member"))
@jwt_required()
def remove_group_member(group_id, user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    if not check_permission(current_user_id, group_id, "kick_user"):
        return {
            "message": "You don't have permission to manage members!"
        }, 403

    try:
        cursor.execute("""
                       DELETE
                       FROM group_member
                       WHERE group_id = %s
                         AND user_id = %s
                       """, (group_id, user_id))

        # Odstránenie používateľa z konverzácie skupiny
        cursor.execute('SELECT conversation_id FROM "group" WHERE id_group = %s', (group_id,))
        conv_data = cursor.fetchone()
        if conv_data and conv_data["conversation_id"]:
            cursor.execute("""
                           DELETE
                           FROM participant
                           WHERE conversation_id = %s
                             AND user_id = %s
                           """, (conv_data["conversation_id"], user_id))

        db.commit()
    except:
        db.rollback()
        return {
            "message": "Failed to remove member!"
        }, 500

    return {
        "message": "Member removed successfully"
    }, 200