from flask import Blueprint
from flask_restx import Namespace

from libs.external_api import ExternalApi

bp = Blueprint("service_api", __name__, url_prefix="/v1")

api = ExternalApi(bp, version="1.0", title="Service API")

service_api_ns = Namespace("service_api", description="Service operations", path="/")

from . import app  # noqa: E402

api.add_namespace(service_api_ns)
