from flask_restx import Namespace, Resource

birds_ns = Namespace("birds")


@birds_ns.route("/")
class Listing(Resource):
    def get(self):
        return []
