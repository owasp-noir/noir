from flask import Blueprint, Flask, request
from flask_login import login_required
from flask_restful import Api, Resource
from funcy import project
from wtforms import Form, PasswordField, StringField

from helpers import (
    legacy_reader,
    nested_rule,
    order_results,
    org_scoped_rule,
    paginate,
    reassigned_rule,
    require_fields,
    versioned_rule,
)

app = Flask(__name__)
routes = Blueprint("app", __name__)
api = Api(app)


def rate_limit(view):
    return view


# Shares a name with a verb method; only a call reaches a helper.
def post(url):
    return request.args.get("module_post_only")


class BaseResource(Resource):
    decorators = [login_required]


class BaseListResource(BaseResource):
    def get(self):
        q = request.args.get("q")
        return order_results(q)


# `get` is inherited from BaseListResource, the guard from BaseResource.
class ItemListResource(BaseListResource):
    def post(self):
        # legacy_reader() is gone; "legacy_reader()" in a string is no call
        note = "see legacy_reader()"
        req = request.get_json(True)
        require_fields(req, ("name", "kind"))
        return note


# A list built on the base class's keeps its guard.
class UserResource(BaseResource):
    decorators = BaseResource.decorators + [rate_limit]

    def post(self, user_id):
        req = request.get_json(True)
        params = project(req, ("email", "display_name"))
        return params


class OpenResource(Resource):
    def get(self):
        return {}


class LoginForm(Form):
    email = StringField("Email")
    password = PasswordField("Password")

    class Meta:
        csrf_field = StringField("csrf")


@routes.route(org_scoped_rule("/login"), methods=["GET", "POST"])
def login(org_slug=None):
    remember = "remember" in request.form
    form = LoginForm(request.form)
    return str(remember and form.validate())


@routes.route(versioned_rule("/legacy"))
def legacy():
    return "never served at /legacy"


@routes.route(reassigned_rule("/reassigned"))
def reassigned():
    return "served at /api/reassigned"


@routes.route(nested_rule("/nested"))
def nested():
    return "served at /v3/nested"


# Two hops: paginate() -> paging.read_page() reads `page`.
@routes.route("/pages")
def pages():
    return paginate()


api.add_resource(ItemListResource, "/items")
api.add_resource(UserResource, "/users/<user_id>")
api.add_resource(OpenResource, "/open")
app.register_blueprint(routes)
