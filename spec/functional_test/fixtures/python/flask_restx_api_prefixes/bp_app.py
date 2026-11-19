from flask import Flask, Blueprint
import flask_restful
from flask_restx import Api, Namespace, Resource

app = Flask(__name__)

# flask-restful "Use With Blueprints": the Api inherits the registration's url_prefix.
api_bp = Blueprint("api", __name__)
api = flask_restful.Api(api_bp)


class TodoItem(flask_restful.Resource):
    def get(self, id):
        return {"task": "Say hello"}


api.add_resource(TodoItem, "/todos/<int:id>")


@api_bp.route("/plain")
def plain():
    return ""


app.register_blueprint(api_bp, url_prefix="/api")

x_bp = Blueprint("x", __name__)
x_api = Api(x_bp)
things_ns = Namespace("things")
x_api.add_namespace(things_ns, path="/things")


@things_ns.route("/list")
class Things(Resource):
    def get(self):
        return []


app.register_blueprint(x_bp, url_prefix="/x")
