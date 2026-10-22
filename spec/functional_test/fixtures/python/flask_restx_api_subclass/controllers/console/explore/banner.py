# `explore/` has no __init__.py (a PEP 420 namespace package), yet the
# absolute import still resolves against the enclosing package's root.
from flask_restx import Resource

from controllers.console import api


class BannerApi(Resource):
    def get(self):
        return []


api.add_resource(BannerApi, "/explore/banners")
