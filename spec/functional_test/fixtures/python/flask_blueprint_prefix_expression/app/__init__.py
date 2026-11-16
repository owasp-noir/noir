from flask import Flask

from . import config
from .config import API_PREFIX
from .views import admin_bp, items_bp, reports_bp, users_bp

ADMIN = "/admin"


def create_app():
    app = Flask(__name__)
    app.register_blueprint(users_bp, url_prefix=API_PREFIX + "/users")
    app.register_blueprint(items_bp, url_prefix=f"{API_PREFIX}/items")
    app.register_blueprint(
        reports_bp,
        url_prefix=config.API_PREFIX + "/reports",
    )
    app.register_blueprint(admin_bp, url_prefix=ADMIN)
    return app
