from flask_restx import Namespace, Resource

fish_ns = Namespace("fish")


@fish_ns.route("/")
class Listing(Resource):
    def get(self):
        return []
