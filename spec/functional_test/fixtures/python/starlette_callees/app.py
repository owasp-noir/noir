from starlette.applications import Starlette
from starlette.routing import Mount, Route
from starlette.responses import JSONResponse, Response
from helpers import save_user


async def create_user(request):
    data = await request.json()
    user_id = request.path_params["user_id"]
    user = save_user(data, user_id)
    audit_log(user)
    return JSONResponse({"id": user_id})


async def health(request):
    return Response("ok")


async def search(request):
    q = request.query_params.get("q")
    token = request.headers.get("X-Token")
    result = run_search(q, token)
    return JSONResponse(result)


async def list_items(request):
    session = request.cookies.get("session")
    items = fetch_items(session)
    audit_log(items)
    return JSONResponse(items)


app = Starlette(routes=[
    Route("/users/{user_id:int}", create_user, methods=["POST"]),
    Route("/health", health),
    Route("/search", endpoint=search, methods=["GET", "POST"]),
    Mount("/api", routes=[
        Route("/items", list_items),
    ]),
])
