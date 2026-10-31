from flask import abort, g, request
from flask_appbuilder import BaseView, ModelRestApi, expose
from flask_appbuilder.api import safe
from flask_appbuilder.security.decorators import has_access, has_access_api, protect

from decorators import api_errors, get_user_id, is_feature_enabled, jwt_positional, maybe_user, read_gate, redirect_to_login


class ChartRestApi(
    ModelRestApi,
):
    resource_name = "chart"
    include_route_methods = {"get_list", "get", "export", "favorite_status", "public_info"}

    @expose("/export/", methods=("GET",))
    @protect()
    @safe
    def export(self, **kwargs):
        return self.response(200, result=[])

    @expose("/favorite_status/", methods=("GET",))
    @read_gate
    def favorite_status(self):
        return self.response(200, result=[])

    @expose("/public_info/", methods=("GET",))
    @maybe_user
    @safe
    def public_info(self):
        return self.response(200, result={})


class PageView(BaseView):
    route_base = "/page"

    @has_access
    @expose("/list/")
    # pylint: disable=no-self-use
    def list(self):
        return self.render_template("list.html")

    @expose("/open/")
    def open(self):
        return self.render_template("open.html")

    @expose("/welcome/")
    def welcome(self):
        if not is_feature_enabled("WELCOME"):
            abort(404)
        if not g.user or not get_user_id():
            return redirect_to_login()
        return self.render_template("welcome.html")

    @expose("/flagged/")
    def flagged(self):
        if not is_feature_enabled("FLAGGED"):
            abort(404)
        return self.render_template("flagged.html")

    @expose("/mixed/", methods=["GET", "POST"])
    def mixed(self):
        if request.method == "GET":
            return "public page"
        if not g.user or g.user.is_anonymous:
            return redirect_to_login()
        return "saved"

    @expose("/post-only-check/")
    def post_only_check(self):
        if not g.user and request.method == "POST":
            return redirect_to_login()
        return "x"

    @expose("/jwt-positional/")
    @jwt_positional
    def jwt_pos(self):
        return "x"

    @expose("/guest-only/")
    def guest_only(self):
        # Sends a logged-in caller away; anyone else gets the page.
        if g.user:
            return redirect_to_login()
        return self.render_template("guest.html")


class Api(BaseView):
    route_base = "/x"

    @api_errors
    @has_access_api
    @expose("/v1/query/", methods=("POST",))
    def query(self):
        return self.json_response({})

    @api_errors
    @expose("/v1/ping/")
    def ping(self):
        return self.json_response({})
