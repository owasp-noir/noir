from quart import Blueprint

orphan_bp = Blueprint("orphan", __name__, url_prefix="/orphan")


@orphan_bp.route("/lonely")
async def lonely():
    return {}
