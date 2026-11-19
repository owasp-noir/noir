from flask_restx import Namespace, Resource

# Named like the Api it is added to.
api = Namespace("cats")


@api.route("/")
class Listing(Resource):
    def get(self):
        return []
