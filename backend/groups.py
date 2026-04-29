from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint, send_file
import io
import uuid
from helper_func import get_current_user_id, db, is_group_member, check_permission, load_yaml, is_valid_image

groups_blueprint = Blueprint('groups', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@groups_blueprint.route('/', methods=['POST'])
@swag_from(load_yaml("documentation/groups.yaml", "create_group"))
@jwt_required()
# Creates a group, its conversation and sets creator as Manager
def create_group():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    name = request.json.get("name")
    capacity = request.json.get("capacity", 10)
    generate_qr = request.json.get("generate_qr", False)

    if not name:
        return {
            "message": "Group name is required!"
        }, 400
    try:
        capacity = int(capacity)
    except (TypeError, ValueError):
        return {
            "message": "Capacity must be a valid number!"
        }, 400

    if capacity < 1:
        return {
            "message": "Capacity must be greater than 0!"
        }, 400
    qr_code = str(uuid.uuid4()) if generate_qr else None

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

            cursor.execute("""INSERT INTO "group" (name, conversation_id, capacity)
                              VALUES (%s, %s, %s) RETURNING id_group""", (name, conv_id, capacity))
            new_group_id = cursor.fetchone()["id_group"]
            if qr_code:
                cursor.execute("""
                               UPDATE "group"
                               SET qr_code = %s
                               WHERE id_group = %s
                               """, (qr_code, new_group_id))

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
                "conversation_id": conv_id,
                "qr_code": qr_code
            }, 201
    except Exception as e:
        db.rollback()
        return {
            "message": "error"
        }, 500


@groups_blueprint.route('/', methods=["GET"])
@swag_from(load_yaml("documentation/groups.yaml", "get_groups"))
@jwt_required()
# Lists groups where the user is a member
def get_groups():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
                   SELECT g.id_group, g.name, g.capacity, g.create_date, (g.icon IS NOT NULL) as has_icon
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
# Gets details of a specific group. Requires membership.
def get_group(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {
            "message": "You are not a member of this group!"
        }, 403

    cursor.execute("""
                   SELECT id_group, name, capacity, create_date, (icon IS NOT NULL) as has_icon, conversation_id, qr_code
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
# This function was edited using AI (Gemini)
# Updates group details. Requires membership and 'manage_group' permission.
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
        capacity = request.json.get("capacity")
    except Exception:
        return {
            "message": "Invalid format!"
        }, 400

    if capacity is not None:
        try:
            capacity = int(capacity)
        except (TypeError, ValueError):
            return {
                "message": "Capacity must be a valid number!"
            }, 400
        if capacity < 1:
            return {
                "message": "Capacity must be greater than 0!"
            }, 400

    try:
        cursor.execute("""
                       UPDATE "group"
                       SET name = COALESCE(%s, name),
                           capacity = COALESCE(%s, capacity)
                       WHERE id_group = %s RETURNING conversation_id
                       """, (name, capacity, group_id))

        updated_group = cursor.fetchone()

        # Ak sa zmenilo meno skupiny, synchronizujeme aj meno konverzÃ¡cie
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
# This function was edited using AI (Gemini)
# Deletes a group and its conversation. Requires membership and 'delete_group' permission.
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
# Lists all members of a group. Requires group membership.
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
                          (us.profile_picture IS NOT NULL) as has_profile_picture
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
# This function was edited using AI (Gemini)
# Adds a new member to a group with role 'Member'. Requires membership and 'add_user' permission.
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

    cursor.execute("""
                    SELECT capacity
                    FROM "group"
                    WHERE id_group = %s
                   """, (group_id,))
    group_result = cursor.fetchone()
    if group_result is None:
        return {
            "message": "Group not found!"
        }, 404

    cursor.execute("""
                    SELECT COUNT(*) AS member_count
                    FROM group_member
                    WHERE group_id = %s
                   """, (group_id,))
    member_count = cursor.fetchone()["member_count"]
    if member_count >= group_result["capacity"]:
        return {
            "message": "Group has reached its capacity!"
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

@groups_blueprint.route('/join', methods=["POST"])
@jwt_required()
def join_group():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    try:
        invite_code = request.json.get("invite_code", "").strip()
    except Exception:
        return {"message": "Invalid format!"}, 400

    if not invite_code:
        return {"message": "Invite code is required!"}, 400

    cursor.execute("""
                    SELECT id_group, capacity, conversation_id
                    FROM "group"
                    WHERE qr_code = %s
                   """, (invite_code,))
    group = cursor.fetchone()
    if group is None:
        return {"message": "Invalid invite code!"}, 404

    group_id = group["id_group"]
    if is_group_member(current_user_id, group_id):
        return {"message": "You are already a member of this group!"}, 400

    cursor.execute("""
                    SELECT COUNT(*) AS member_count
                    FROM group_member
                    WHERE group_id = %s
                   """, (group_id,))
    member_count = cursor.fetchone()["member_count"]
    if member_count >= group["capacity"]:
        return {"message": "Group has reached its capacity!"}, 400

    try:
        cursor.execute("""
                        INSERT INTO group_member (group_id, user_id)
                        VALUES (%s, %s)
                       """, (group_id, current_user_id))

        cursor.execute("""
                        SELECT id_role
                        FROM role
                        WHERE group_id = %s AND name = %s
                       """, (group_id, 'Member'))
        role_result = cursor.fetchone()

        if role_result:
            role_id = role_result["id_role"]
        else:
            cursor.execute("""
                            INSERT INTO role (group_id, name, color)
                            VALUES (%s, %s, %s)
                            RETURNING id_role
                           """, (group_id, 'Member', '#808080'))
            role_id = cursor.fetchone()["id_role"]
            cursor.execute("""
                            INSERT INTO role_permission (role_id, permission_id, value)
                            SELECT %s, id_permission, FALSE
                            FROM permission
                           """, (role_id,))

        cursor.execute("""
                        INSERT INTO user_role (user_id, role_id)
                        VALUES (%s, %s)
                       """, (current_user_id, role_id))

        if group["conversation_id"]:
            cursor.execute("""
                            INSERT INTO participant (conversation_id, user_id)
                            VALUES (%s, %s)
                           """, (group["conversation_id"], current_user_id))

        db.commit()
    except Exception:
        db.rollback()
        return {"message": "Failed to join group!"}, 500

    return {"message": "Joined group successfully"}, 200

@groups_blueprint.route('/<int:group_id>/invite', methods=["GET"])
@jwt_required()
def get_group_invite(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    cursor.execute("""
                    SELECT qr_code
                    FROM "group"
                    WHERE id_group = %s
                   """, (group_id,))
    result = cursor.fetchone()
    if result is None:
        return {"message": "Group not found!"}, 404

    return {
        "message": "Success",
        "qr_code": result["qr_code"]
    }, 200

@groups_blueprint.route('/<int:group_id>/invite', methods=["POST"])
@jwt_required()
def enable_group_invite(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {"message": "You don't have permission to manage this group!"}, 403

    cursor.execute("""
                    SELECT qr_code
                    FROM "group"
                    WHERE id_group = %s
                   """, (group_id,))
    result = cursor.fetchone()
    if result is None:
        return {"message": "Group not found!"}, 404

    qr_code = result["qr_code"] or str(uuid.uuid4())

    try:
        cursor.execute("""
                        UPDATE "group"
                        SET qr_code = %s
                        WHERE id_group = %s
                       """, (qr_code, group_id))
        db.commit()
    except Exception:
        db.rollback()
        return {"message": "Failed to enable invite QR code!"}, 500

    return {
        "message": "Invite QR code enabled successfully",
        "qr_code": qr_code
    }, 200

@groups_blueprint.route('/<int:group_id>/invite', methods=["DELETE"])
@jwt_required()
def disable_group_invite(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {"message": "You don't have permission to manage this group!"}, 403

    try:
        cursor.execute("""
                        UPDATE "group"
                        SET qr_code = NULL
                        WHERE id_group = %s
                       """, (group_id,))
        db.commit()
    except Exception:
        db.rollback()
        return {"message": "Failed to disable invite QR code!"}, 500

    return {"message": "Invite QR code disabled successfully"}, 200


@groups_blueprint.route('/<int:group_id>/members/<int:user_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/groups.yaml", "remove_group_member"))
@jwt_required()
# This function was edited using AI (Gemini)
# Removes a member from a group and its conversation. Requires membership and 'kick_user' permission.
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
                        DELETE FROM user_role 
                        WHERE user_id = %s
                          AND role_id IN (
                              SELECT id_role FROM role WHERE group_id = %s
                          )
                        """, (user_id, group_id))
        cursor.execute("""
                       DELETE
                       FROM group_member
                       WHERE group_id = %s
                         AND user_id = %s
                       """, (group_id, user_id))

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


@groups_blueprint.route('/<int:group_id>/icon', methods=["GET"])
@swag_from(load_yaml("documentation/groups.yaml", "get_group_icon"))
@jwt_required()
# Downloads group icon as binary stream. Requires group membership.
def get_group_icon(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    cursor.execute('SELECT icon FROM "group" WHERE id_group = %s', (group_id,))
    result = cursor.fetchone()
    if not result or not result["icon"]:
        return {"message": "No icon found for this group"}, 404

    return send_file(
        io.BytesIO(result["icon"]),
        mimetype='image/png'
    )

@groups_blueprint.route('/<int:group_id>/icon', methods=["DELETE"])
@swag_from(load_yaml("documentation/groups.yaml", "delete_group_icon"))
@jwt_required()
# Removes group icon. Requires 'manage_group' permission.
def delete_group_icon(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {"message": "You don't have permission to manage this group!"}, 403

    try:
        cursor.execute('UPDATE "group" SET icon = NULL WHERE id_group = %s', (group_id,))
        db.commit()
        return {"message": "Group icon removed successfully"}
    except:
        db.rollback()
        return {"message": "Failed to remove group icon!"}, 500


@groups_blueprint.route('/<int:group_id>/icon', methods=["PUT"])
@swag_from(load_yaml("documentation/groups.yaml", "update_group_icon"))
@jwt_required()
# Function below was created with help of AI.
# Uploads group icon as multipart/form-data. Requires 'manage_group' permission. Only JPEG/PNG allowed.
def upload_group_icon(group_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not is_group_member(current_user_id, group_id):
        return {"message": "You are not a member of this group!"}, 403

    if not check_permission(current_user_id, group_id, "manage_group"):
        return {"message": "You don't have permission to manage this group!"}, 403

    file = request.files.get('image')
    if not file:
        return {"message": "No image file provided!"}, 400

    data = file.read()
    if not is_valid_image(data):
        return {"message": "Invalid format! Only JPEG and PNG are supported."}, 400

    try:
        cursor.execute('UPDATE "group" SET icon = %s WHERE id_group = %s', (data, group_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to upload group icon!"}, 500

    return {"message": "Group icon uploaded successfully"}