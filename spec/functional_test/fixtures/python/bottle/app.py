from bottle import Bottle, route, get, post, request, run

app = Bottle()


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


# Module-qualified call: bottle.route used directly.
@route('/search', method='GET')
def search():
    q = request.query['q']
    page = request.query.get('page')
    return [q, page]


if __name__ == '__main__':
    run(app, host='localhost', port=8080)
