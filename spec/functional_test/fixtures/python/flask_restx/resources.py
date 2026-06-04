from flask_restx import Namespace, Resource

# The namespace and its routes live in a DIFFERENT file from the
# Blueprint + Api wiring (app.py). The blueprint's url_prefix
# (`/api/v1`) and the add_namespace mount (`/users`) are only visible
# in app.py, so resolving these routes requires cross-file propagation
# of the namespace prefix.
users_ns = Namespace("users", description="user operations")


@users_ns.route("/<int:user_id>")
class UserDetail(Resource):
    def get(self, user_id):
        return {}

    def delete(self, user_id):
        return {}


@users_ns.route("/me")
class CurrentUser(Resource):
    def get(self):
        return {}
