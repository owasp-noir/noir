from bottle import Bottle, route, get, post, request, run

app = Bottle()
admin_app = Bottle()
api_app = Bottle()
nested_admin_app = Bottle()


# Bare decorator — uses the module's default app.
@route('/ping')
def ping():
    name = request.query.get('name')
    age = request.query.age
    return f"pong {name} {age}"


# Bare method-specific decorator.
@get('/admin')
def admin():
    token = request.get_cookie('abcd_token')
    return "ok"


@post('/submit')
def submit():
    username = request.forms.username
    password = request.forms.get('password')
    user_agent = request.headers.get('User-Agent')
    return "submitted"


# Instance-bound decorator with methods list.
@app.route('/login', method=['POST'])
def login():
    username = request.json.get('username')
    password = request.json['password']
    return {"ok": bool(username and password)}


# Path parameters via <name> and <name:type>.
@app.get('/users/<id:int>')
def get_user(id):
    return {"id": id}


@admin_app.get('/dashboard')
def admin_dashboard():
    section = request.query.get('section')
    return {"section": section}


@admin_app.post('/reports/<report_id:int>')
def admin_report(report_id):
    body = request.json
    title = body.get('title')
    return {"id": report_id, "title": title}


@nested_admin_app.get('/metrics/<metric_id:int>')
def nested_metric(metric_id):
    window = request.query.get('window')
    return {"id": metric_id, "window": window}


# Module-qualified call: bottle.route used directly.
@route('/search', method='GET')
def search():
    q = request.query['q']
    page = request.query.get('page')
    return [q, page]


@route(path='/keyword/login', method='POST')
def keyword_login():
    token = request.headers.get('X-Login-Token')
    payload = request.json
    username = payload.get('username')
    return {"token": token, "username": username}


@get(path='/keyword/status/<status_id:int>')
def keyword_status(status_id):
    region = request.query.get('region')
    return {"status_id": status_id, "region": region}


@route(
    '/bulk',
    method=[
        'PUT',
        'PATCH',
    ],
)
def bulk_update():
    body = request.json
    action = body['action']
    return {"action": action}


def programmatic_health():
    probe = request.query.get('probe')
    return {"probe": probe}


app.route('/health', method='GET', callback=programmatic_health)
api_app.mount('/admin', nested_admin_app)
app.mount('/admin', admin_app)
app.mount('/api', api_app)


if __name__ == '__main__':
    run(app, host='localhost', port=8080)
