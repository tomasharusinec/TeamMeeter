from flask import Flask
from authorization import authorization_blueprint
from groups import groups_blueprint
from helper_func import get_current_user_id
from users import users_blueprint
from roles import roles_blueprint
from conversations import conversations_blueprint
import os
from flask_jwt_extended import JWTManager
from flasgger import Swagger

app = Flask(__name__)

template = {
    "openapi": "3.0.3",
    "info": {
        "title": "TeamMeeter's API",
        "version": "1.0.0",
    },
    "components": {
        "securitySchemes": {
            "Bearer": {
                "type": "http",
                "scheme": "bearer",
                "bearerFormat": "JWT",
                "description": 'Enter the token'
            }
        }
    }
}

app.config['SWAGGER'] = {
    'title': "TeamMeeter's API",
    'uiversion': 3,
    'openapi': '3.0.3'
}

swagger = Swagger(app, template=template)
app.config['JWT_SECRET_KEY'] = os.getenv("JWT_SECRET_KEY")
jwt = JWTManager(app)

@jwt.user_lookup_loader
def user_lookup_callback(_jwt_header, jwt_data):
    identity = jwt_data["sub"]
    return get_current_user_id(identity)

app.register_blueprint(authorization_blueprint, url_prefix='/authorization')
app.register_blueprint(users_blueprint, url_prefix='/users')
app.register_blueprint(groups_blueprint, url_prefix='/groups')
app.register_blueprint(conversations_blueprint, url_prefix="/conversations")
app.register_blueprint(roles_blueprint, url_prefix="/roles")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)