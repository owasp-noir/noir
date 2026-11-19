from flask_restx import Namespace, Resource

# Named like the Api it is added to.
api = Namespace("dogs")


@api.route("/")
class Listing(Resource):
    def get(self):
        return []
