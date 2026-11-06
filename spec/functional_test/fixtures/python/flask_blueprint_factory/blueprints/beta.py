from flask import Blueprint


def make():
    beta_bp = Blueprint("beta", __name__)

    @beta_bp.route("/beta")
    def h():
        return ""

    return beta_bp
