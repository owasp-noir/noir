from flask import Flask
from flask_restful import Api, Resource

from resources import ItemResource, ItemListResource


class ScopedApi(Api):
    # App-specific wrapper around add_resource (mirrors redash's
    # ApiExt.add_org_resource). The analyzer must treat this delegating
    # method as an add_resource equivalent.
    def add_scoped_resource(self, resource, *urls, **kwargs):
        return self.add_resource(resource, *urls, **kwargs)


app = Flask(__name__)
api = ScopedApi(app)


class Ping(Resource):
    def get(self):
        return {"pong": True}


# Same-file Resource registered by the standard helper. The verb is
# inferred from the class body (only `get` is defined).
api.add_resource(Ping, "/ping")

# Cross-file Resource (defined in resources.py) carrying a path param.
api.add_resource(ItemResource, "/items/<int:item_id>", endpoint="item")

# Multi-line call + multiple URLs + the app-specific wrapper. Both URLs
# expand to every verb the Resource defines.
api.add_scoped_resource(
    ItemListResource,
    "/items",
    "/items/all",
    endpoint="items",
)

# `Api(prefix=...)` prepends the prefix to every resource registered on it.
prefixed_api = Api(app, prefix="/api/v2")


class Health(Resource):
    def get(self):
        return {"ok": True}


prefixed_api.add_resource(Health, "/health")
