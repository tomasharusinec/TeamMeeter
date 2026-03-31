from flask import request
from flask_jwt_extended import create_access_token
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db

authorization_blueprint = Blueprint('authorization', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@authorization_blueprint.route('/register', methods=["POST"])
def register():
    try:
        firstname = request.json["firstname"]
        surname = request.json["surname"]
        username = request.json["username"]
        password = request.json["password"]
        email = request.json["email"]
        birthdate = request.json["birthdate"]
    except:
        return {
            "-1": "Invalid register format!"
        }

    create_user_cmd = """
        INSERT INTO "user" (username, password, email)
        VALUES (%s, %s, %s)
        RETURNING id_registration
    """

    create_user_settings_cmd = """
        INSERT INTO user_setting (id_user, name, surname, birthdate)
        VALUES (%s, %s, %s, %s)
    """

    cursor.execute('SELECT username FROM "user" WHERE username = %s', (username,))
    if cursor.fetchone():
        return {"-1": "Username already taken"}

    cursor.execute('SELECT email FROM "user" WHERE email = %s', (email,))
    if cursor.fetchone():
        return {"-1": "This email was already used!"}

    try:
        cursor.execute(create_user_cmd, (username, password, email))
        user_id = cursor.fetchone()["id_registration"]
        cursor.execute(create_user_settings_cmd, (user_id, firstname, surname, birthdate))
        db.commit()
    except:
        db.rollback()
        return {"-2": "User already exists!"}

    return {"1": "Success"}


@authorization_blueprint.route('/login', methods=["POST"])
def login():
    try:
        username = request.json["username"]
        password = request.json["password"]
    except:
        return {
            "-1": "Invalid login format!"
        }

    cursor.execute('SELECT id_registration, username, password FROM "user" WHERE username = %s', (username,))
    output = cursor.fetchone()
    if output is None:
        return {"-1": "This username does not exist!"}
    elif output["password"] != password:
        return {"-2": "Wrong password!"}

    access_token = create_access_token(identity=username)
    return {"1": "Success", "token": access_token}