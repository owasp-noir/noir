from flask_restx import Namespace, Resource

ns = Namespace("users")


@ns.route("/list")
class Listing(Resource):
    def get(self):
        return []
