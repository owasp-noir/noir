from flask_appbuilder import BaseView
from flask_appbuilder import BaseView as AppBuilderBaseView
from flask_appbuilder.api import BaseApi, expose
from flask_appbuilder.views import IndexView


class DatabaseRestApi(BaseApi):
    resource_name = "database"

    @expose("/<int:pk>/connection", methods=("GET",))
    def connection(self, pk):
        return {}

    @expose("/", methods=("POST",))
    def create(self):
        return {}


class AnnotationLayerView(BaseView):
    route_base = "/annotationlayer"

    @expose("/list/")
    def list(self):
        return ""

    @expose("/<int:pk>/annotation")
    def get(self, pk):
        return ""


class ReportApi(BaseApi):
    """No resource_name: FAB falls back to the lowercased class name."""

    version = "v2"

    @expose("/summary", methods=("GET",))
    def summary(self):
        return {}


class HealthView(AppBuilderBaseView):
    """No route_base: FAB falls back to /<class name lowercased>."""

    @expose("/status")
    def status(self):
        return ""


class SupersetIndexView(IndexView):
    """IndexView pins route_base = "" inside Flask-AppBuilder itself."""

    @expose("/welcome")
    def welcome(self):
        return ""
