from flask import Blueprint, Flask
from flask.views import MethodView

from forum.utils.helpers import register_if_enabled, register_v2, register_view, remember_view
from vendored.routing import mount_routes

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

    # A helper that rewrites the rule or registers under a condition, a
    # built list of routes, and an unread helper handed no view: no row.
    other = Blueprint("other", __name__)
    register_v2(other, routes=["/pref"], view_func=Overview.as_view("pref"))
    register_if_enabled(other, routes=["/maybe"], view_func=Overview.as_view("maybe"), enabled=True)
    register_view(other, routes=["/r%d" % i for i in range(3)], view_func=Overview.as_view("r"))
    mount_routes(other, routes=["/unread"])
    app.register_blueprint(other, url_prefix="/other")

    # The env default, and a key only two non-default classes set (one
    # row per value).
    message = Blueprint("message", __name__)
    register_view(message, routes=["/inbox"], view_func=Overview.as_view("inbox"))
    app.register_blueprint(message, url_prefix=app.config["MESSAGE_URL_PREFIX"])
    api = Blueprint("api", __name__)
    register_view(api, routes=["/status"], view_func=Overview.as_view("status"))
    app.register_blueprint(api, url_prefix=app.config["API_URL_PREFIX"])


app = Flask(__name__)
app.config.from_object("forum.configs.default.DefaultConfig")
load_blueprints(app)
