from flask_restx import Namespace, Resource

from controllers.base import TokenResource
from controllers.wraps import (
    admin_only,
    admins_only,
    admission,
    during_event,
    inner_key_only,
    members_only,
    session_required,
    signup_enabled,
    visibility_gate,
)

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


@ns.route("/members/<int:member_id>")
class MemberApi(Resource):
    @admission(
        roles=["owner"],
    )
    def delete(self, member_id):
        return {}


@ns.route("/audit/<int:entry_id>")
class Audit(Resource):
    @session_required
    @admin_only
    def get(self, entry_id):
        return {}


@ns.route("/dashboard")
class Dashboard(Resource):
    @members_only
    def get(self):
        return {}


@ns.route("/stats")
class Stats(Resource):
    @admins_only
    def get(self):
        return {}


@ns.route("/scores")
class Scores(Resource):
    @visibility_gate
    def get(self):
        return {}


@ns.route("/live")
class Live(Resource):
    @during_event
    def get(self):
        return {}
