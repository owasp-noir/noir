from flask import Blueprint

bp = Blueprint("users", __name__)


@bp.get("/")
def index():
    return "x"
