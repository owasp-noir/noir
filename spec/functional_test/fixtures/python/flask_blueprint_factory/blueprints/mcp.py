from flask import Blueprint


def construct_blueprint():
    bp = Blueprint("mcp", __name__)

    @bp.route("/", methods=["POST"])
    def endpoint():
        return ""

    return bp
