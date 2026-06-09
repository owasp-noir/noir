from flask import Flask, Blueprint
from flask_restx import Api

from resources import users_ns

app = Flask(__name__)
api_bp = Blueprint("api", __name__, url_prefix="/b")
api = Api(api_bp)
api.add_namespace(users_ns, "/users")
app.register_blueprint(api_bp)
