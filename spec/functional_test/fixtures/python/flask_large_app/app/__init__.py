# The "large application" layout: blueprints are declared in each
# package's __init__.py, their routes live in a sibling views.py, and the
# app factory imports and registers them inside create_app().
from flask import Flask
from .api.users import bp as users_bp


def create_app():
    app = Flask(__name__)

    from .auth import auth as auth_blueprint
    app.register_blueprint(auth_blueprint, url_prefix="/auth")

    from .main import main
    app.register_blueprint(main)

    from app.views import posts
    app.register_blueprint(posts.bp, url_prefix="/posts")

    app.register_blueprint(users_bp, url_prefix="/api/v1/users")
    return app
