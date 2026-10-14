from flask import Blueprint

bp = Blueprint("posts", __name__)


@bp.route("/<int:id>")
def show(id):
    return "x"
