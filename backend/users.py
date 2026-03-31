from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db

users_blueprint = Blueprint('users', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@users_blueprint.route('/', methods=["GET"])
@swag_from('../documentation/index.yaml')
@jwt_required()
def get_users():
    cursor.execute("""
        SELECT u.id_registration, u.username, u.email, u.registration_date,
               us.name, us.surname, us.birthdate, us.profile_picture
        FROM "user" u
        JOIN user_setting us ON u.id_registration = us.id_user
    """)
    users = cursor.fetchall()
    return {"1": "Success", "users": users}


@users_blueprint.route('/<int:user_id>', methods=["GET"])
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
        return {"-1": "User not found!"}
    return {"1": "Success", "user": user}

@users_blueprint.route('/<int:user_id>', methods=["PUT"])
@jwt_required()
def update_user(user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)
    if current_user_id != user_id:
        return {"-1": "You can only update your own profile!"}

    try:
        name = request.json.get("name")
        surname = request.json.get("surname")
        birthdate = request.json.get("birthdate")
        profile_picture = request.json.get("profile_picture")
    except:
        return {"-1": "Invalid format!"}

    try:
        cursor.execute("""
            UPDATE user_setting SET
                name = COALESCE(%s, name),
                surname = COALESCE(%s, surname),
                birthdate = COALESCE(%s, birthdate),
                profile_picture = COALESCE(%s, profile_picture)
            WHERE id_user_setting = (SELECT id_user_settings FROM "user" WHERE id_registration = %s)
        """, (name, surname, birthdate, profile_picture, user_id))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to update user!"}

    return {"1": "User updated successfully"}


@users_blueprint.route('/<int:user_id>', methods=["DELETE"])
@jwt_required()
def delete_user(user_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)
    if current_user_id != user_id:
        return {"-1": "You can only delete your own account!"}

    try:
        cursor.execute('DELETE FROM "user" WHERE id_registration = %s', (user_id,))
        db.commit()
    except:
        db.rollback()
        return {"-2": "Failed to delete user!"}

    return {"1": "User deleted successfully"}