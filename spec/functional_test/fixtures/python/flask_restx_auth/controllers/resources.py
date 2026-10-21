from flask_restx import Namespace, Resource

from controllers.base import TokenResource
from controllers.wraps import admission, inner_key_only, session_required, signup_enabled

ns = Namespace("v1")


# A decorator named like flask-login's that checks nothing.
def login_required(view):
    return view


@ns.route("/profile")
class Profile(Resource):
    @ns.doc("profile")
    @session_required
    def get(self):
        return {}


@ns.route("/items/<int:item_id>")
class Item(TokenResource):
    def get(self, item_id):
        return {}


@ns.route("/settings")
class Settings(Resource):
    @admission(signup=False)
    def put(self):
        return {}


@ns.route("/inner/sync")
class InnerSync(Resource):
    @inner_key_only
    def post(self):
        return {}


@ns.route("/signup")
class Signup(Resource):
    @signup_enabled
    @login_required
    def post(self):
        return {}
