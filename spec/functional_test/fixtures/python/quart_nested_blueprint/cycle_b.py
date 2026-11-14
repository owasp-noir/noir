from quart import Blueprint
from cycle_a import cycle_a_bp

cycle_b_bp = Blueprint("cycle_b", __name__, url_prefix="/cb")
cycle_b_bp.register_blueprint(cycle_a_bp)


@cycle_b_bp.route("/b")
async def b():
    return {}
