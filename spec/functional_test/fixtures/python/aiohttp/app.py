from aiohttp import web

import external_handlers

routes = web.RouteTableDef()
admin_routes = web.RouteTableDef()


async def index(request):
    return web.Response(text="hello")


async def list_users(request):
    page = request.query.get('page')
    return web.Response(text=f"users page={page}")


async def create_user(request):
    data = await request.json()
    name = data['name']
    email = data.get('email')
    return web.Response(text=f"created {name} {email}")


async def update_user(request):
    user_id = request.match_info['id']
    form = await request.post()
    role = form['role']
    return web.Response(text=f"updated {user_id} {role}")


async def delete_user(request):
    user_id = request.match_info.get('id')
    return web.Response(text=f"deleted {user_id}")


async def alias_user(request):
    alias_id = request.match_info['alias_id']
    return web.Response(text=f"alias {alias_id}")


async def websocket_feed(request):
    channel = request.match_info['channel']
    token = request.query.get('token')
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    await ws.send_str(f"{channel}:{token}")
    return ws


class ReportView(web.View):
    async def get(self):
        report_id = self.request.match_info['id']
        verbose = self.request.query.get('verbose')
        return web.Response(text=f"report {report_id} verbose={verbose}")

    async def post(self):
        data = await self.request.json()
        title = data['title']
        return web.Response(text=f"created report {title}")


class AuditView(web.View):
    async def get(self):
        audit_id = self.request.match_info['audit_id']
        page = self.request.query.get('page')
        return web.Response(text=f"audit {audit_id} page={page}")

    async def delete(self):
        audit_id = self.request.match_info['audit_id']
        token = self.request.headers['X-Audit-Token']
        return web.Response(text=f"delete audit {audit_id} token={token}")


@routes.view('/decorated/{item_id}')
class DecoratedView(web.View):
    async def get(self):
        item_id = self.request.match_info['item_id']
        return web.Response(text=f"decorated {item_id}")

    async def patch(self):
        data = await self.request.json()
        status = data.get('status')
        return web.Response(text=f"decorated status {status}")


@routes.get('/admin')
async def admin_panel(request):
    token = request.cookies['session']
    user_agent = request.headers.get('User-Agent')
    return web.Response(text=f"admin {token} {user_agent}")


@routes.post('/login')
async def login(request):
    data = await request.json()
    username = data['username']
    password = data['password']
    return web.Response(text=f"login {username} {password}")


@routes.route('PUT', '/profile')
async def update_profile(request):
    form = await request.post()
    bio = form.get('bio')
    return web.Response(text=f"profile {bio}")


@routes.get('/search/{category}')
async def search(request):
    category = request.match_info['category']
    q = request.rel_url.query.get('q')
    return web.Response(text=f"search {category} q={q}")


@admin_routes.get('/stats')
async def admin_stats(request):
    section = request.query.get('section')
    return web.Response(text=f"admin stats {section}")


async def admin_health(request):
    check = request.match_info['check']
    return web.Response(text=f"admin health {check}")


async def tenant_detail(request):
    tenant_id = request.match_info['tenant_id']
    expand = request.query.get('expand')
    return web.Response(text=f"tenant {tenant_id} {expand}")


async def tenant_create(request):
    data = await request.json()
    name = data['name']
    return web.Response(text=f"tenant {name}")


tenant_routes = [
    web.get('/tenants/{tenant_id}', tenant_detail),
    web.post('/tenants', tenant_create),
    web.patch('/external/{external_id}', external_handlers.external_patch),
]


def setup_routes(app):
    app.router.add_get('/', index)
    app.router.add_get('/users', list_users)
    app.router.add_post('/users', create_user)
    app.router.add_put('/users/{id}', update_user)
    app.router.add_delete('/users/{id}', delete_user)
    app.router.add_route('PATCH', '/users/{id}', update_user)
    add_route = app.router.add_route
    add_route('GET', '/alias/{alias_id}', alias_user, name='alias-user')
    add_route('*', '/wildcard', index, name='wildcard')
    app.router.add_get('/feed/{channel}', websocket_feed)
    app.router.add_routes([web.view('/reports/{id}', ReportView)])
    app.router.add_static('/assets/', path='static')


def setup_admin_routes(admin_app):
    admin_app.add_routes(admin_routes)
    admin_app.router.add_get('/health/{check}', admin_health)
    admin_app.router.add_view('/audit/{audit_id}', AuditView)
    admin_app.router.add_static('/static/', path='admin_static')


def main():
    app = web.Application()
    admin_app = web.Application()
    tenant_app = web.Application()
    setup_routes(app)
    setup_admin_routes(admin_app)
    tenant_app.router.add_routes(tenant_routes)
    app.add_subapp('/admin', admin_app)
    app.add_subapp('/tenant-api', tenant_app)
    app.router.add_routes(routes)
    web.run_app(app)


if __name__ == '__main__':
    main()
