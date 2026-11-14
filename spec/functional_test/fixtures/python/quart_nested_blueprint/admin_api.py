from quart import Blueprint

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


@admin_bp.route("/users")
async def users():
    return {}
