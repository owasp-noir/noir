from quart import Blueprint

chat_bp = Blueprint("chat", __name__, url_prefix="/genai")


@chat_bp.route("/ask", methods=["POST"])
async def ask():
    return {}
