from robyn import Robyn, SubRouter

app = Robyn(__file__)


@app.get("/users")
async def list_users():
    return {"users": []}


@app.post("/users")
async def create_user(request):
    data = request.json()
    name = data["name"]
    email = data.get("email")
    return {"created": True}


# Path-param syntax `:name` — Robyn's convention; the analyzer normalizes
# this to Noir's `{name}` form.
@app.get("/users/:id")
async def get_user(request):
    return {"id": request.path_params["id"]}


@app.put("/users/:id")
async def update_user(request):
    body = request.json()
    bio = body["bio"]
    return {"updated": True}


@app.delete("/users/:id")
async def delete_user(request):
    return {"deleted": True}


@app.patch("/users/:id/profile")
async def patch_profile(request):
    return {"patched": True}


# Query + header access patterns.
@app.get("/search")
async def search(request):
    q = request.query_params.get("q")
    page = request.query_params["page"]
    ua = request.headers.get("User-Agent")
    return {"q": q, "page": page, "ua": ua}


# Websocket route — surfaced as a GET endpoint.
@app.get("/ws")
async def websocket_endpoint():
    return {"ws": True}


@app.websocket("/live/:room_id")
async def live_updates():
    return {"live": True}


# SubRouter with positional `/api` prefix; routes under it inherit the
# `/api` mount.
api = SubRouter(__file__, "/api")
admin = SubRouter(__file__, "/admin")


@api.get("/items")
async def list_items():
    return {"items": []}


@api.post("/items/:item_id/tags")
async def tag_item(request):
    tag = request.json().get("tag")
    priority = request.json()["priority"]
    return {"ok": True}


@admin.get("/metrics/:metric_id")
async def admin_metric(request):
    window = request.query_params.get("window")
    return {"window": window}


v2 = SubRouter(
    __file__,
    "/v2",
)


@v2.get("/reports/:report_id")
async def get_report(request):
    include = request.query_params.get("include")
    return {"include": include}


api.include_router(admin)
app.include_router(api)
app.include_router(v2)


if __name__ == "__main__":
    app.start(port=8080)
