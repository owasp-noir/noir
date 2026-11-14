from quart import Blueprint
from leaf_api import leaf_bp

mid_bp = Blueprint("mid", __name__, url_prefix="/mid")
mid_bp.register_blueprint(leaf_bp)


@mid_bp.route("/ping")
async def ping():
    return {}
