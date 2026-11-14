from quart import Blueprint

shared_bp = Blueprint("shared", __name__, url_prefix="/shared")


@shared_bp.route("/status")
async def status():
    return {}
