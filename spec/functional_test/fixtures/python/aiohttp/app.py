from aiohttp import web

routes = web.RouteTableDef()


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


def setup_routes(app):
    app.router.add_get('/', index)
    app.router.add_get('/users', list_users)
    app.router.add_post('/users', create_user)
    app.router.add_put('/users/{id}', update_user)
    app.router.add_delete('/users/{id}', delete_user)
    app.router.add_route('PATCH', '/users/{id}', update_user)


def main():
    app = web.Application()
    setup_routes(app)
    app.router.add_routes(routes)
    web.run_app(app)


if __name__ == '__main__':
    main()
