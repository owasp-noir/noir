from flask import Flask
from flask_restx import Api

from project.apis.users import ns as users_ns
from project.apis.orders import ns as orders_ns
from project.apiv1 import blueprint as api1
from project.v2 import rest_api
from project.restful import restful_api

app = Flask(__name__)

# Every module names its namespace `ns`.
rest = Api(app, prefix="/api/v1")
rest.add_namespace(users_ns, path="/users")
rest.add_namespace(orders_ns, path="/orders")

app.register_blueprint(api1)

# Apis built without an app, bound later.
rest_api.init_app(app)
restful_api.init_app(app)
