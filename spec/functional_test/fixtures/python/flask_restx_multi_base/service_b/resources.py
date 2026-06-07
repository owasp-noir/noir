from flask_restx import Namespace, Resource

users_ns = Namespace("users")


@users_ns.route("/items")
class Items(Resource):
    def get(self):
        return {}
