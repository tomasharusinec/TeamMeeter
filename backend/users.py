from datetime import datetime
from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint, send_file
import io
from helper_func import get_current_user_id, db, load_yaml, is_valid_image

users_blueprint = Blueprint('users', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@users_blueprint.route('/<int:user_id>', methods=["GET"])
@swag_from(load_yaml("documentation/users.yaml", "get_user_by_id"))
@jwt_required()
# Gets public and profile info for a specific user. Requires valid JWT.
def get_user(user_id):
    cursor.execute("""
        SELECT u.id_registration, u.username, u.email, u.registration_date, us.name, us.surname, us.birthdate, (us.profile_picture IS NOT NULL) as has_profile_picture
        FROM "user" u
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE u.id_registration = %s
    """, (user_id,))
    user = cursor.fetchone()
    if user is None:
        return {"message": "User not found!"}, 404
    return {"message": "Success", "user": user}

@users_blueprint.route('/me', methods=["PUT"])
@swag_from(load_yaml("documentation/users.yaml", "update_my_profile"))
@jwt_required()
# Updates settings and personal info for the current user.
def update_my_profile():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)

    try:
        name = request.json.get("name")
        surname = request.json.get("surname")
        birthdate_str = request.json.get("birthdate")
        email = request.json.get("email")
    except:
        return {"message": "Invalid format!"}, 400

    if email:
        cursor.execute('SELECT id_registration FROM "user" WHERE email = %s AND id_registration != %s', (email, user_id))
        if cursor.fetchone():
            return {"message": "Email is already taken!"}, 409

    if birthdate_str:
        try:
            birthdate = datetime.strptime(birthdate_str, '%Y-%m-%d').date()
            today = datetime.now().date()
            if birthdate > today:
                return {"message": "Invalid birthdate"}, 400
        except ValueError:
            return {"message": "Invalid birthdate format. Use YYYY-MM-DD."}, 400

    try:
        if email:
            cursor.execute('UPDATE "user" SET email = %s WHERE id_registration = %s', (email, user_id))

        cursor.execute("""
            UPDATE user_setting SET
                name = COALESCE(%s, name),
                surname = COALESCE(%s, surname),
                birthdate = COALESCE(%s, birthdate)
            WHERE id_user = %s
        """, (name, surname, birthdate_str, user_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to update user!"}, 500

    return {"message": "User updated successfully"}


@users_blueprint.route('/me', methods=["DELETE"])
@swag_from(load_yaml("documentation/users.yaml", "delete_my_profile"))
@jwt_required()
# Permanently deletes current user account.
def delete_my_profile():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)

    try:
        cursor.execute('DELETE FROM "user" WHERE id_registration = %s', (user_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete user!"}, 500

    return {"message": "User deleted successfully"}


@users_blueprint.route('/<int:user_id>/profile-picture', methods=["GET"])
@swag_from(load_yaml("documentation/users.yaml", "get_profile_picture"))
@jwt_required()
# Function below was created with help of AI.
# Downloads profile picture as binary stream.
def get_profile_picture(user_id):
    cursor.execute('SELECT profile_picture FROM user_setting WHERE id_user = %s', (user_id,))
    result = cursor.fetchone()
    if not result or not result["profile_picture"]:
        return {"message": "No profile picture found"}, 404

    return send_file(
        io.BytesIO(result["profile_picture"]),
        mimetype='image/png'
    )


@users_blueprint.route('/me/profile-picture', methods=["PUT"])
@swag_from(load_yaml("documentation/users.yaml", "update_my_profile_picture"))
@jwt_required()
# Uploads new profile picture for current user. Only JPEG/PNG allowed.
def upload_my_profile_picture():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)

    file = request.files.get('image')
    if not file:
        return {"message": "No image file provided!"}, 400

    data = file.read()
    if not is_valid_image(data):
        return {"message": "Invalid format! Only JPEG and PNG are supported."}, 400

    try:
        cursor.execute('UPDATE user_setting SET profile_picture = %s WHERE id_user = %s', (data, user_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to upload profile picture!"}, 500

    return {"message": "Profile picture uploaded successfully"}


@users_blueprint.route('/me', methods=["GET"])
@swag_from(load_yaml("documentation/users.yaml", "get_my_profile"))
@jwt_required()
# Gets current user profile info.
def get_my_profile():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    return get_user(user_id)


@users_blueprint.route('/me/profile-picture', methods=["DELETE"])
@swag_from(load_yaml("documentation/users.yaml", "delete_my_profile_picture"))
@jwt_required()
# Removes profile picture.
def delete_my_profile_picture():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    try:
        cursor.execute('UPDATE user_setting SET profile_picture = NULL WHERE id_user = %s', (user_id,))
        db.commit()
        return {"message": "Profile picture removed successfully"}
    except:
        db.rollback()
        return {"message": "Failed to remove profile picture!"}, 500


@users_blueprint.route('/me/profile-picture', methods=["GET"])
@swag_from(load_yaml("documentation/users.yaml", "get_my_profile_picture"))
@jwt_required()
# Downloads own profile picture.
def get_my_profile_picture():
    identity = get_jwt_identity()
    user_id = get_current_user_id(identity)
    return get_profile_picture(user_id)