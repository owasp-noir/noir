from flask import Flask, Blueprint
from flask_restx import Api

from resources import users_ns

app = Flask(__name__)

# Blueprint carries the API version prefix; the Api is mounted onto it.
api_bp = Blueprint("api", __name__, url_prefix="/api/v1")

# Multi-line Api(...) constructor — the blueprint argument sits on a
# continuation line, which the route-detection regex must coalesce to
# link the `/api/v1` prefix to this Api instance.
api = Api(
    api_bp,
    version="1.0",
    title="Demo API",
    doc="/docs",
)

# Explicit mount path; combined with the blueprint url_prefix this makes
# every users_ns route resolve under `/api/v1/users`.
api.add_namespace(users_ns, "/users")

app.register_blueprint(api_bp)
