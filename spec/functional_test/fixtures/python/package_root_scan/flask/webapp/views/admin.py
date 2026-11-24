from flask import Blueprint, request
from flask_login import login_required

admin_bp = Blueprint("admin", __name__)


@admin_bp.route("/reports", methods=["GET"])
@login_required
def reports():
    period = request.args.get("period")
    return "ok"
