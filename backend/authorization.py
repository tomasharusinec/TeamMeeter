from flasgger import swag_from
from flask import request
from flask_jwt_extended import create_access_token
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, load_yaml
from werkzeug.security import generate_password_hash, check_password_hash

authorization_blueprint = Blueprint('authorization', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

@authorization_blueprint.route("/register", methods=["POST"])
@swag_from(load_yaml("documentation/authorization.yaml", "register"))
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
            "message": "Invalid register format!",
        }, 400

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
        return {"message": "Username already taken"}, 409

    cursor.execute('SELECT email FROM "user" WHERE email = %s', (email,))
    if cursor.fetchone():
        return {"message": "This email was already used!"}, 409

    try:
        hashed_password = generate_password_hash(password)
        cursor.execute(create_user_cmd, (username, hashed_password, email))
        user_id = cursor.fetchone()["id_registration"]
        cursor.execute(create_user_settings_cmd, (user_id, firstname, surname, birthdate))
        db.commit()
    except:
        db.rollback()
        return {"message": "User already exists!"}, 409

    return {"message": "Success"}, 201


@authorization_blueprint.route("/login", methods=["POST"])
@swag_from(load_yaml("documentation/authorization.yaml", "login"))
def login():
    try:
        username = request.json["username"]
        password = request.json["password"]
    except:
        return {
            "message": "Invalid login format!"
        }, 400

    cursor.execute('SELECT id_registration, username, password FROM "user" WHERE username = %s', (username,))
    output = cursor.fetchone()
    if output is None or not check_password_hash(output["password"], password):
        return {"message": "Invalid credentials!"}, 401

    access_token = create_access_token(identity=username)
    return {"message": "Success", "token": access_token}, 200