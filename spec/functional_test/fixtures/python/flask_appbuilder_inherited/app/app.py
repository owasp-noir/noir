from flask import Flask
from flask_appbuilder import AppBuilder

from app.css_templates import CssTemplateRestApi
from app.dashboards import DashboardRestApi

app = Flask(__name__)
appbuilder = AppBuilder(app)
appbuilder.add_api(DashboardRestApi)
appbuilder.add_api(CssTemplateRestApi)
