from flask import Flask
from authorization import authorization_blueprint
from groups import groups_blueprint
from users import users_blueprint
import os
from flask_jwt_extended import JWTManager
from flasgger import Swagger

app = Flask(__name__)
swagger = Swagger(app)
app.config['JWT_SECRET_KEY'] = os.getenv("JWT_SECRET_KEY")
jwt = JWTManager(app)

app.register_blueprint(authorization_blueprint, url_prefix='/authorization')
app.register_blueprint(users_blueprint, url_prefix='/users')

app.register_blueprint(groups_blueprint, url_prefix='/groups')

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)