from quart import Quart


def create_app():
    app = Quart(__name__)

    from .auth import auth as auth_blueprint
    app.register_blueprint(auth_blueprint, url_prefix="/auth")

    from .main import main
    app.register_blueprint(main)
    return app
