from flask import Blueprint


# Same local name as mcp.py's factory: each file keeps its own prefix.
def construct_blueprint():
    bp = Blueprint("rss", __name__)

    @bp.route("/feed")
    def feed():
        return ""

    return bp
