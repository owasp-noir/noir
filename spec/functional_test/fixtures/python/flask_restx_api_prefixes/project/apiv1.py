from flask import Blueprint
from flask_restx import Api

from .apis.cats import api as ns1
from .apis.dogs import api as ns2

blueprint = Blueprint("api", __name__, url_prefix="/api/1")
api = Api(blueprint,
    title="My Title",
    version="1.0",
)

api.add_namespace(ns1)
api.add_namespace(ns2, path="/prefix/of/ns2")
