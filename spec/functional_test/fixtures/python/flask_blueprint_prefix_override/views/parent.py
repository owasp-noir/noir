from flask import Blueprint

shared = Blueprint("shared", __name__)
shared_child = Blueprint("shared_child", __name__)


@shared_child.route("/cr")
def cr():
    return ""


# `shared` is registered twice from app.py; its child follows both.
shared.register_blueprint(shared_child, url_prefix="/c")
