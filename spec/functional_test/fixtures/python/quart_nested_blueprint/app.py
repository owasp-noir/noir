from quart import Quart, Blueprint
from chat_api import chat_bp
from admin_api import admin_bp
from deep_api import mid_bp
from shared_api import shared_bp

app = Quart(__name__)
root_bp = Blueprint("root", __name__, url_prefix="/chatbot")
root_bp.register_blueprint(chat_bp)
root_bp.register_blueprint(admin_bp, url_prefix="/manage")
root_bp.register_blueprint(mid_bp)
root_bp.register_blueprint(shared_bp)

other_bp = Blueprint("other", __name__, url_prefix="/other")
other_bp.register_blueprint(shared_bp)


@root_bp.route("/health")
async def health():
    return {}


app.register_blueprint(root_bp)
app.register_blueprint(other_bp)
