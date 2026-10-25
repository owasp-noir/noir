from flask import Blueprint, Flask, request
from flask_login import login_required
from flask_restful import Api, Resource
from funcy import project
from wtforms import Form, PasswordField, StringField

from helpers import order_results, org_scoped_rule, require_fields, versioned_rule

app = Flask(__name__)
routes = Blueprint("app", __name__)
api = Api(app)


def rate_limit(view):
    return view


class BaseResource(Resource):
    decorators = [login_required]


class BaseListResource(BaseResource):
    def get(self):
        q = request.args.get("q")
        return order_results(q)


# `get` is inherited from BaseListResource, the guard from BaseResource.
class ItemListResource(BaseListResource):
    def post(self):
        req = request.get_json(True)
        require_fields(req, ("name", "kind"))
        return {}


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


@routes.route(org_scoped_rule("/login"), methods=["GET", "POST"])
def login(org_slug=None):
    remember = "remember" in request.form
    form = LoginForm(request.form)
    return str(remember and form.validate())


@routes.route(versioned_rule("/legacy"))
def legacy():
    return "never served at /legacy"


api.add_resource(ItemListResource, "/items")
api.add_resource(UserResource, "/users/<user_id>")
api.add_resource(OpenResource, "/open")
app.register_blueprint(routes)
