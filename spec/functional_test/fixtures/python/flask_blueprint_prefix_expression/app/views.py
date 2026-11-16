from flask import Blueprint

users_bp = Blueprint("users", __name__)
items_bp = Blueprint("items", __name__)
reports_bp = Blueprint("reports", __name__)
admin_bp = Blueprint("admin", __name__)


@users_bp.route("/<int:user_id>")
def get_user(user_id):
    return {}


@items_bp.post("/")
def create_item():
    return {}, 201


@reports_bp.get("/daily")
def daily_report():
    return {}


@admin_bp.get("/stats")
def stats():
    return {}
