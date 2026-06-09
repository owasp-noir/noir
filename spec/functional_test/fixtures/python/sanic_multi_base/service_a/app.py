from sanic import Blueprint, Sanic, response

app = Sanic("service_a")
api = Blueprint("api", url_prefix="/items")


@api.get("/a-only")
async def list_a_items(request):
    return response.json([])


app.blueprint(api, url_prefix="/a")
