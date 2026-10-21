from flask_restx import Resource

from controllers.console import console_ns


@console_ns.route("/workspaces/current/members")
class MemberListApi(Resource):
    def get(self):
        return {}
