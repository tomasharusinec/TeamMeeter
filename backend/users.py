from datetime import datetime
from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, load_yaml

users_blueprint = Blueprint('users', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@users_blueprint.route('/<int:user_id>', methods=["GET"])
@swag_from(load_yaml("documentation/users.yaml", "get_user_by_id"))
@jwt_required()
def get_user(user_id):
    cursor.execute("""
        SELECT u.id_registration, u.username, u.email, u.registration_date,
               us.name, us.surname, us.birthdate, us.profile_picture
        FROM "user" u
        JOIN user_setting us ON u.id_registration = us.id_user
        WHERE u.id_registration = %s
    """, (user_id,))
    user = cursor.fetchone()
    if user is None:
        return {"message": "User not found!"}
    return {"message": "Success", "user": user}

@users_blueprint.route('/<int:user_id>', methods=["PUT"])
@swag_from(load_yaml("documentation/users.yaml", "update_user"))
@jwt_required()
def update_user(user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)
    if current_user_id != user_id:
        return {"message": "You can only update your own profile!"}

    try:
        name = request.json.get("name")
        surname = request.json.get("surname")
        birthdate_str = request.json.get("birthdate")
        profile_picture = request.json.get("profile_picture")
    except:
        return {"message": "Invalid format!"}

    if birthdate_str:

        birthdate = datetime.strptime(birthdate_str, '%Y-%m-%d').date()

        today = datetime.now().date()

        if birthdate > today:
            return {"message": "Invalid birthdate"}, 400

    try:
        cursor.execute("""
            UPDATE user_setting SET
                name = COALESCE(%s, name),
                surname = COALESCE(%s, surname),
                birthdate = COALESCE(%s, birthdate),
                profile_picture = COALESCE(%s, profile_picture)
            WHERE id_user_setting = (SELECT id_user_settings FROM "user" WHERE id_registration = %s)
        """, (name, surname, birthdate_str, profile_picture, user_id))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to update user!"}

    return {"message": "User updated successfully"}


@users_blueprint.route('/<int:user_id>', methods=["DELETE"])
@swag_from(load_yaml("documentation/users.yaml", "delete_user"))
@jwt_required()
def delete_user(user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)
    if current_user_id != user_id:
        return {"message": "You can only delete your own account!"}

    try:
        cursor.execute('DELETE FROM "user" WHERE id_registration = %s', (user_id,))
        db.commit()
    except:
        db.rollback()
        return {"message": "Failed to delete user!"}

    return {"message": "User deleted successfully"}