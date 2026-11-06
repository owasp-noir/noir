from flask import Blueprint


def make():
    alpha_bp = Blueprint("alpha", __name__)

    @alpha_bp.route("/alpha")
    def h():
        return ""

    return alpha_bp
