from sanic import Blueprint, Sanic, response

app = Sanic("service_b")
api = Blueprint("api", url_prefix="/items")


@api.get("/b-only")
async def list_b_items(request):
    return response.json([])


app.blueprint(api, url_prefix="/b")
