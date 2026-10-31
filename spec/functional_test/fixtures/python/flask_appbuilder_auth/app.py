from flask import Flask
from flask_appbuilder import AppBuilder

from views import Api, ChartRestApi, PageView

app = Flask(__name__)
appbuilder = AppBuilder(app)
appbuilder.add_api(ChartRestApi)
appbuilder.add_view_no_menu(PageView)
appbuilder.add_view_no_menu(Api)
