from flask_restx import Resource

from controllers.service_api import service_api_ns


@service_api_ns.route("/parameters")
class AppParameterApi(Resource):
    def get(self):
        return {}
