# Blueprints built by factory functions (`def construct_blueprint(...)`
# returning a local Blueprint), registered from the app with a url_prefix,
# and one factory blueprint mounted on another one declared in a second file.
from flask import Flask

import blueprints.alpha as alpha
import blueprints.beta as beta
import blueprints.mcp as mcp
import blueprints.pair as pair
import blueprints.rss as rss
import blueprints.tags as tags
from blueprints.settings import construct_blueprint as construct_settings


def create_app():
    app = Flask(__name__)
    app.register_blueprint(tags.construct_blueprint(None), url_prefix="/tags")
    app.register_blueprint(
        construct_settings(None), url_prefix="/settings"
    )
    mcp_blueprint = mcp.construct_blueprint()
    app.register_blueprint(mcp_blueprint, url_prefix="/mcp/v1")
    app.register_blueprint(
        # url_prefix="/old"
        rss.construct_blueprint(), url_prefix="/rss"
    )
    return app


def register_more(app):
    app.register_blueprint(pair.make_a(), url_prefix="/a")
    app.register_blueprint(pair.make_b(), url_prefix="/b")
    # One local rebound: each registration takes the nearest binding.
    bp = alpha.make()
    app.register_blueprint(bp, url_prefix="/A")
    bp = beta.make()
    app.register_blueprint(bp, url_prefix="/B")


def register_flagged(app, flag):
    bp = alpha.make()

    def helper():
        bp = beta.make()
        return bp

    # Registered under an `if`: the nested helper's `bp` is not this one.
    if flag:
        app.register_blueprint(bp, url_prefix="/F")
