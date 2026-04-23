from starlette.applications import Starlette
from starlette.routing import Route, Mount
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


async def homepage(request):
    return Response("Hello")


async def get_user(request):
    user_id = request.path_params['user_id']
    return Response(f"User {user_id}")


async def submit(request):
    data = await request.json()
    name = request.query_params.get('name')
    token = request.headers['X-Token']
    session = request.cookies.get('session')
    return JSONResponse({"ok": True})


async def search(request):
    q = request.query_params['q']
    return JSONResponse({"q": q})


async def list_items(request):
    return JSONResponse([])


async def get_item(request):
    item_id = request.path_params['id']
    return JSONResponse({"id": item_id})


async def upload(request):
    form = await request.form()
    return JSONResponse({"ok": True})


async def profile(request):
    name = request.path_params['name']
    return Response(name)


app = Starlette(routes=[
    Route('/', homepage),
    Route('/users/{user_id}', get_user),
    Route('/submit', submit, methods=['GET', 'POST']),
    Route('/search', search),
    Route('/upload', upload, methods=['POST']),
    Route('/profile/{name:str}', profile),
    Mount('/api', routes=[
        Route('/items', list_items),
        Route('/items/{id:int}', get_item),
    ]),
])
