from flask_appbuilder import BaseView
from flask_appbuilder.api import BaseApi, expose


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
