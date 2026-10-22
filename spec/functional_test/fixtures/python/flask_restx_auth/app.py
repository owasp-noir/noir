from flask import Flask
from flask_restx import Api

from controllers.resources import ns

app = Flask(__name__)
api = Api(app)
api.add_namespace(ns, "/v1")
