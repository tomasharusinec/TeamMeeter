from flask import Flask, request
from flask_jwt_extended import JWTManager, create_access_token, jwt_required
import os
from dotenv import load_dotenv
import psycopg2


app = Flask(__name__)
load_dotenv()

db = psycopg2.connect(host = "localhost", port = "5432", user = "postgres", password = os.getenv("MY_PASS"), database = "postgres")

cursor = db.cursor()
cursor.execute("""
        CREATE TABLE IF NOT EXISTS Users (
            id INT PRIMARY KEY,
            name VARCHAR(255),
            gender VARCHAR(255)
    );
""")
db.commit()

app.config['JWT_SECRET_KEY'] = os.getenv("JWT_SECRET_KEY")
jwt = JWTManager(app)

username = os.getenv("DB_USER")
password = os.getenv("DB_PASSWD")

@app.route('/login', methods=["POST"])
def login():
    try:
        loaded_username = request.json["username"]
        loaded_passwd = request.json["password"]
    except:
        return {
            "-1": "Invalid login format!"
        }

    if loaded_username != username or password != loaded_passwd:
        return {
            "-2": "Wrong credentials!"
        }

    token = create_access_token(username)
    return {
        "access_token": token
    }

@app.route('/unprotected')
def index():
    return {
        "1": "You successfully accessed unprotected endpoint!"
    }

@app.route('/protected/<id>', methods=["GET"])
@jwt_required()
def protected_get(id):
    cursor.execute("""SELECT * FROM Users WHERE id = %s""", (id,))
    user = cursor.fetchone()
    return {
        "1": user
    }

@app.route('/protected/get_all', methods=["GET"])
@jwt_required()
def get_all_users():
    cursor.execute(
        """
            SELECT * FROM Users
        """
    )
    users = cursor.fetchall()
    users_dict = {}
    i = 1
    for user in users:
        users_dict[i] = user
        i += 1

    return users_dict


@app.route('/protected', methods=["POST"])
@jwt_required()
def protected_post():
    id = request.json["id"]
    name = request.json["name"]
    gender = request.json["gender"]

    try:
        cursor.execute("""
                INSERT INTO Users (id, name, gender) 
                VALUES (%s, %s, %s)
            """, (id, name, gender)
        )
    except:
        return {
            "-1": "Insert zlyhal"
        }

    db.commit()
    return {
        "1": "Successfully inserted in database!"
    }

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)