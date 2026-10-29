from flask_appbuilder.api import expose

from app.base_api import BaseResourceApi


class DashboardRestApi(BaseResourceApi):
    resource_name = "dashboard"

    @expose("/<pk>/charts", methods=("GET",))
    def get_charts(self, pk):
        return self.response(200)
