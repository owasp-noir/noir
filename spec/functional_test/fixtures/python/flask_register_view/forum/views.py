from flask import Blueprint, Flask
from flask.views import MethodView

from forum.utils.helpers import register_view, remember_view

ADMIN_URL_PREFIX = "/not-the-config"


class ViewTopic(MethodView):
    def get(self, topic_id, slug=None):
        return "topic"

    def post(self, topic_id, slug=None):
        return "reply"


class Login(MethodView):
    def get(self):
        return "form"

    def post(self):
        return "login"


class Overview(MethodView):
    def get(self):
        return "overview"


def raw_post(post_id):
    return "raw"


def load_blueprints(app):
    """Register the blueprints, e.g.

    register_view(user, routes=["/from-docstring"], view_func=Login.as_view("doc"))
    """
    user = Blueprint("user", __name__)
    register_view(
        user,
        routes=["/topic/<int:topic_id>", "/topic/<int:topic_id>-<slug>"],
        view_func=ViewTopic.as_view("view_topic"),
    )
    register_view(
        user,
        routes=["/login"],
        view_func=Login.as_view(
            "login", manager_factory=lambda: None
        ),
    )
    register_view(user, routes=["/post/<int:post_id>/raw"], view_func=raw_post, methods=["GET", "POST"])
    remember_view(user, routes=["/sitemap-only"], view_func=Login.as_view("sitemap_login"))
    # register_view(user, routes=["/commented"], view_func=Login.as_view("commented"))
    app.register_blueprint(user, url_prefix=app.config["USER_URL_PREFIX"])

    admin = Blueprint("admin", __name__)
    register_view(admin, routes=["/"], view_func=Overview.as_view("overview"))
    app.register_blueprint(admin, url_prefix=app.config.get("ADMIN_URL_PREFIX", "/fallback"))


app = Flask(__name__)
app.config.from_object("forum.configs.default.DefaultConfig")
load_blueprints(app)
