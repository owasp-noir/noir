import external_views

from starlette.applications import Starlette
from starlette.endpoints import HTTPEndpoint, WebSocketEndpoint
from starlette.routing import Route, Mount, Router, WebSocketRoute
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.staticfiles import StaticFiles


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


async def admin_dashboard(request):
    section = request.query_params.get('section')
    return JSONResponse({"section": section})


async def internal_status(request):
    region = request.query_params.get('region')
    return JSONResponse({"region": region})


async def audit_entry(request):
    entry_id = request.path_params['entry_id']
    source = request.query_params.get('source')
    return JSONResponse({"entry_id": entry_id, "source": source})


async def nested_metric(request):
    metric_id = request.path_params['metric_id']
    window = request.query_params.get('window')
    return JSONResponse({"metric_id": metric_id, "window": window})


async def chat_socket(websocket):
    room = websocket.path_params['room']
    token = websocket.query_params.get('token')
    await websocket.accept()
    await websocket.send_json({"room": room, "token": token})
    await websocket.close()


class ReportEndpoint(HTTPEndpoint):
    async def get(self, request):
        report_id = request.path_params['report_id']
        include = request.query_params.get('include')
        return JSONResponse({"report_id": report_id, "include": include})

    async def post(self, request):
        payload = await request.json()
        title = payload['title']
        return JSONResponse({"title": title})


class NotificationSocket(WebSocketEndpoint):
    async def on_connect(self, websocket):
        topic = websocket.path_params['topic']
        client = websocket.headers.get('X-Client')
        await websocket.accept()


admin_routes = [
    Route('/dashboard', admin_dashboard),
    Route('/reports/{report_id:int}', ReportEndpoint),
]

internal_routes = [
    Route('/status', internal_status),
]

v1_routes = [
    Route('/metrics/{metric_id:int}', nested_metric),
]

nested_routes = [
    Mount('/v1', routes=v1_routes),
]

# A variable-assigned route list that ALSO holds an *inline* Mount. The
# list-range lookup used to short-circuit the inline mount stack, so
# `/billing/invoices` lost its '/billing' prefix. Mounted under '/accounts'
# below, both prefixes must compose: '/accounts' + '/billing'.
account_routes = [
    Route('/overview', internal_status),
    Mount('/billing', routes=[
        Route('/invoices', list_items),
    ]),
]

internal_app = Starlette(routes=internal_routes)
programmatic_app = Router()
programmatic_app.add_route('/audit/{entry_id:int}', audit_entry, methods=['GET'])
programmatic_app.add_websocket_route('/ws/{room}', chat_socket)


app = Starlette(routes=[
    Route('/', homepage),
    Route('/users/{user_id}', get_user),
    Route('/submit', submit, methods=['GET', 'POST']),
    Route('/search', search),
    Route('/upload', upload, methods=['POST']),
    Route('/profile/{name:str}', profile),
    Route('/external/{item_id:int}', external_views.external_item),
    Route('/reports/{report_id:int}', ReportEndpoint),
    Mount('/api', routes=[
        Route('/items', list_items),
        Route('/items/{id:int}', get_item),
    ]),
    Mount('/admin', routes=admin_routes),
    Mount('/accounts', routes=account_routes),
    Mount('/internal', app=internal_app),
    Mount('/nested', routes=nested_routes),
    Mount('/programmatic', app=programmatic_app),
    Mount(
        '/assets',
        app=StaticFiles(directory='public'),
        name='assets',
    ),
    WebSocketRoute('/ws/{room}', chat_socket),
    WebSocketRoute('/notifications/{topic:str}', NotificationSocket),
])
