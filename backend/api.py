from flask import Flask, request
from flask_jwt_extended import JWTManager, create_access_token
import os
from dotenv import load_dotenv

app = Flask(__name__)
load_dotenv()

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

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)