# A Blueprint subclass keeps Sanic's constructor, so the url_prefix and the
# version passed to it still shape every route registered on the instance.
from sanic import Blueprint, Sanic, response


class ApiBlueprint(Blueprint):
    pass


items = ApiBlueprint("items", version=2, url_prefix="/items")
health = ApiBlueprint("health", version=3)


@items.get("/list")
async def list_items(request):
    return response.json([])


@health.get("/ping")
async def ping(request):
    return response.text("ok")


app = Sanic("subclass")
app.blueprint(items)
app.blueprint(health)
