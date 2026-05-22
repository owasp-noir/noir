from starlette.responses import JSONResponse


async def external_item(request):
    item_id = request.path_params["item_id"]
    q = request.query_params.get("q")
    payload = await request.json()
    title = payload.get("title")
    return JSONResponse({"item_id": item_id, "q": q, "title": title})
