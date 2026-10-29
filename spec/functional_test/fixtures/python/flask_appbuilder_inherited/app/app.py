from flask import Flask
from flask_appbuilder import AppBuilder

from app.css_templates import CssTemplateRestApi
from app.dashboards import DashboardRestApi
from app.views import DashboardModelView, ExploreView

app = Flask(__name__)
appbuilder = AppBuilder(app)
appbuilder.add_api(DashboardRestApi)
appbuilder.add_api(CssTemplateRestApi)
appbuilder.add_view(ExploreView, "Explore")
appbuilder.add_view(DashboardModelView, "Dashboards")

# A loop variable names no class; it is not registration evidence.
extra_apis = []
for api in extra_apis:
    appbuilder.add_api(api)
