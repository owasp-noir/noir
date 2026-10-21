from flask import Blueprint
from flask_restx import Namespace

from libs.external_api import ExternalApi

# Every package names its blueprint `bp`; each Api must take its own.
bp = Blueprint("console", __name__, url_prefix="/console/api")

api = ExternalApi(
    bp,
    version="1.0",
    title="Console API",
)

console_ns = Namespace("console", description="Console operations", path="/")

from . import members  # noqa: E402
from .explore import banner  # noqa: E402

api.add_namespace(console_ns)
