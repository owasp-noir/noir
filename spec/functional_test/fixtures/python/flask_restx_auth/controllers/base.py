from flask_restx import Resource

from controllers.wraps import token_required


class TokenResource(Resource):
    method_decorators = [token_required]
