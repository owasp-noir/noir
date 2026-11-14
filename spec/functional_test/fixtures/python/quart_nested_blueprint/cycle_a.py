from quart import Blueprint
from cycle_b import cycle_b_bp

cycle_a_bp = Blueprint("cycle_a", __name__, url_prefix="/ca")
cycle_a_bp.register_blueprint(cycle_b_bp)


@cycle_a_bp.route("/a")
async def a():
    return {}
