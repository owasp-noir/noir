from flask import Blueprint, Flask, abort, request
from flask_login import current_user, login_required

app = Flask(__name__)
admin_bp = Blueprint("admin", __name__, url_prefix="/admin")
account_bp = Blueprint("account", __name__, url_prefix="/account")
docs_bp = Blueprint("docs", __name__, url_prefix="/docs")
late_bp = Blueprint("late", __name__, url_prefix="/late")


@admin_bp.before_request
@login_required
def require_login():
    pass


@account_bp.before_request
def require_account():
    if not current_user.is_authenticated:
        abort(401)


@docs_bp.before_request
def require_docs_login():
    if request.endpoint == "docs.index":
        return
    if not current_user.is_authenticated:
        abort(401)


@login_required
@late_bp.before_request
def never_wrapped():
    pass


@admin_bp.route("/stats")
def stats():
    return {}


@account_bp.route("/settings", methods=["POST"])
def settings():
    return {}


@docs_bp.route("/")
def index():
    return "docs"


@late_bp.route("/x")
def late():
    return "x"


@app.route("/public")
def public():
    return "public"


app.register_blueprint(admin_bp)
app.register_blueprint(account_bp)
app.register_blueprint(docs_bp)
app.register_blueprint(late_bp)
