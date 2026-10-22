from flask import Blueprint, Flask
from flask_restx import Api


# An in-repo Api subclass keeps Api's app/blueprint argument.
class ExternalApi(Api):
    def __init__(self, app: Blueprint | Flask, *args, **kwargs):
        super().__init__(app, *args, **kwargs)
