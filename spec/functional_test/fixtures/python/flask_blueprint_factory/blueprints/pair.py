from flask import Blueprint


# Two factories building the same local name: neither is given the
# other's prefix.
def make_a():
    bp = Blueprint("a", __name__)

    @bp.route("/pa")
    def pa():
        return ""

    return bp


def make_b():
    bp = Blueprint("b", __name__)

    @bp.route("/pb")
    def pb():
        return ""

    return bp
