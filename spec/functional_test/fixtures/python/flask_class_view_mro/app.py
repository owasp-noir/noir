from flask import Flask, request
from flask.views import MethodView, View
from flask_login import login_required
from flask_restful import Api, Resource

app = Flask(__name__)
api = Api(app)


# A plain View serves every method through its own dispatch_request; a
# base's helper named `get` is not a verb.
class CachedView(View):
    def get(self, key):
        return request.args.get("cache_key")


class Page(CachedView):
    decorators = [login_required]

    def dispatch_request(self):
        return request.args.get("page")


# The registered class's decorators decide an inherited verb's guard.
class BaseThing(Resource):
    def get(self):
        return {}


class AdminThing(BaseThing):
    decorators = [login_required]


class PublicThing(BaseThing):
    pass


class MethodGuarded(BaseThing):
    method_decorators = [login_required]


class AuthMixin:
    decorators = [login_required]


class MixedIn(AuthMixin, BaseThing):
    pass


# Set after the class body.
class LateView(MethodView):
    def get(self):
        return "x"


LateView.decorators = [login_required]


# An empty list on the subclass opens what the base guards.
class GuardedView(MethodView):
    decorators = [login_required]

    def get(self):
        return "x"


class OpenView(GuardedView):
    decorators = []


# C3: Diamond(Left, Right) runs Right.get, not Base.get through Left.
class Left(BaseThing):
    pass


class Right(BaseThing):
    def get(self):
        return "right"


class Diamond(Left, Right):
    pass


app.add_url_rule("/page", view_func=Page.as_view("page"))
api.add_resource(AdminThing, "/admin")
api.add_resource(PublicThing, "/public")
api.add_resource(MethodGuarded, "/method-guarded")
api.add_resource(MixedIn, "/mixed")
app.add_url_rule("/late", view_func=LateView.as_view("late"))
app.add_url_rule("/open", view_func=OpenView.as_view("open"))
api.add_resource(Diamond, "/diamond")
