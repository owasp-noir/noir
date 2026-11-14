from quart import Blueprint

leaf_bp = Blueprint("leaf", __name__, url_prefix="/leaf")


@leaf_bp.route("/item")
async def item():
    return {}
