from datetime import datetime
import os
import uuid
from flasgger import swag_from
from flask import request
from flask_jwt_extended import create_access_token
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import db, load_yaml
from werkzeug.security import generate_password_hash, check_password_hash
try:
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token as google_id_token
except Exception:
    google_requests = None
    google_id_token = None

authorization_blueprint = Blueprint('authorization', __name__)


# Function below was generated using AI (Gemini)
# Produces a unique username from a Google-derived base, appending numeric suffixes if needed.
def _generate_unique_username(base_username: str, cursor) -> str:
    normalized = (base_username or "google_user").strip().lower().replace(" ", "_")
    if not normalized:
        normalized = "google_user"
    normalized = normalized[:40]
    candidate = normalized
    suffix = 1
    while True:
        cursor.execute('SELECT 1 FROM "user" WHERE username = %s', (candidate,))
        if cursor.fetchone() is None:
            return candidate
        candidate = f"{normalized[:35]}_{suffix}"
        suffix += 1


@authorization_blueprint.route("/register", methods=["POST"])
@swag_from(load_yaml("documentation/authorization.yaml", "register"))
# Registers a new user and returns JWT token. Publicly accessible.
def register():
    try:
        firstname = request.json["firstname"]
        surname = request.json["surname"]
        username = request.json["username"]
        password = request.json["password"]
        email = request.json["email"]
        birthdate_str = request.json["birthdate"]
    except:
        return {
            "message": "Invalid register format!",
        }, 400

    if birthdate_str:
        birthdate = datetime.strptime(birthdate_str, '%Y-%m-%d').date()
        today = datetime.now().date()
        if birthdate > today:
            return {"message": "Dátum narodenia nemôže byť v budúcnosti!"}, 400

    create_user_cmd = """
        INSERT INTO "user" (username, password, email)
        VALUES (%s, %s, %s)
        RETURNING id_registration
    """

    create_user_settings_cmd = """
        INSERT INTO user_setting (id_user, name, surname, birthdate)
        VALUES (%s, %s, %s, %s)
    """

    with db.cursor(cursor_factory=RealDictCursor) as cursor:
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
            cursor.execute(
                create_user_settings_cmd,
                (user_id, firstname, surname, birthdate_str),
            )
            db.commit()
        except:
            db.rollback()
            return {"message": "User already exists!"}, 409

    access_token = create_access_token(identity=username)
    return {"message": "Success", "token": access_token}, 200


@authorization_blueprint.route("/login", methods=["POST"])
@swag_from(load_yaml("documentation/authorization.yaml", "login"))
# Verifies credentials and returns JWT token. Publicly accessible.
def login():
    try:
        username = request.json["username"]
        password = request.json["password"]
    except:
        return {
            "message": "Invalid login format!"
        }, 400

    with db.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            'SELECT id_registration, username, password FROM "user" WHERE username = %s',
            (username,),
        )
        output = cursor.fetchone()
        if output is None or not check_password_hash(output["password"], password):
            return {"message": "Invalid credentials!"}, 401

    access_token = create_access_token(identity=username)
    return {"message": "Success", "token": access_token}, 200


@authorization_blueprint.route("/google-login", methods=["POST"])
@swag_from(load_yaml("documentation/authorization.yaml", "google_login"))
# Function below was generated using AI (Gemini)
# Verifies Google ID token, creates or loads user, and returns JWT access token.
def google_login():
    if google_requests is None or google_id_token is None:
        return {"message": "Google SSO is not available on backend."}, 501

    try:
        id_token_value = request.json["id_token"]
    except Exception:
        return {"message": "Invalid google login format!"}, 400

    client_id = os.getenv("GOOGLE_CLIENT_ID")
    if not client_id:
        return {"message": "GOOGLE_CLIENT_ID is not configured on backend."}, 500

    try:
        payload = google_id_token.verify_oauth2_token(
            id_token_value,
            google_requests.Request(),
            client_id,
        )
    except Exception:
        return {"message": "Invalid Google token!"}, 401

    email = payload.get("email")
    if not email:
        return {"message": "Google account has no email."}, 401

    # New / first-time Google accounts may omit the claim or send false until
    # verification completes; blocking caused "works on second try" UX.
    if payload.get("email_verified") is False:
        return {"message": "Google account email is not verified."}, 401

    given_name = payload.get("given_name") or "Google"
    family_name = payload.get("family_name") or "User"

    try:
        with db.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                'SELECT id_registration, username FROM "user" WHERE email = %s',
                (email,),
            )
            existing = cursor.fetchone()
            if existing is None:
                local_part = email.split("@")[0]
                username = _generate_unique_username(local_part, cursor)
                random_password = generate_password_hash(uuid.uuid4().hex)
                cursor.execute(
                    """
                INSERT INTO "user" (username, password, email)
                VALUES (%s, %s, %s)
                RETURNING id_registration
                """,
                    (username, random_password, email),
                )
                user_id = cursor.fetchone()["id_registration"]
                cursor.execute(
                    """
                INSERT INTO user_setting (id_user, name, surname, birthdate)
                VALUES (%s, %s, %s, %s)
                """,
                    (user_id, given_name, family_name, None),
                )
                db.commit()
            else:
                username = existing["username"]
                db.commit()
    except Exception:
        db.rollback()
        return {"message": "Failed to create/login Google user."}, 500

    access_token = create_access_token(identity=username)
    return {"message": "Success", "token": access_token}, 200
