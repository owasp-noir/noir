from flask_appbuilder import BaseView, ModelRestApi, expose
from flask_appbuilder.api import safe
from flask_appbuilder.security.decorators import has_access, has_access_api, protect

from decorators import api_errors, maybe_user, read_gate


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
