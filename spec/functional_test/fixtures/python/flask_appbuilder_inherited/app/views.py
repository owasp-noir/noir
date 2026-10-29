from flask_appbuilder import BaseView, ModelView, expose

from app.constants import RouteMethod


class ExploreView(BaseView):
    route_base = "/explore"

    # Stacked decorators: both routes are served.
    @expose("/<int:id>/", methods=("GET",))
    @expose("/", methods=("GET",))
    def explore(self, id=None):
        return self.render_template("explore.html")


class DashboardModelView(ModelView):
    route_base = "/dashboard"
    include_route_methods = RouteMethod.CRUD_SET | {  # see (FAB docs
        "download",
    }

    @expose("/list/")
    def list(self):
        return self.render_template("list.html")

    @expose("/hidden/")
    def hidden(self):
        return self.render_template("hidden.html")
