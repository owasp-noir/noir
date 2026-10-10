from chalice import Chalice, CognitoUserPoolAuthorizer

from chalicelib.admin import admin_bp
from chalicelib import reports

app = Chalice(app_name='helloworld')
REPORTS_PREFIX = '/reports'
authorizer = CognitoUserPoolAuthorizer('MyPool', provider_arns=['arn:aws:cognito-idp:us-east-1:1:userpool/x'])

app.register_blueprint(admin_bp, url_prefix='/admin')
app.register_blueprint(reports.bp, url_prefix=REPORTS_PREFIX)


@app.route('/')
def index():
    return {'hello': 'world'}


@app.route('/users/{name}', methods=['GET', 'PUT'])
def user(name):
    body = app.current_request.json_body
    q = app.current_request.query_params.get('q')
    return {'name': name, 'q': q, 'body': body}


@app.route('/orders', methods=['POST'], authorizer=authorizer)
def create_order():
    request = app.current_request
    order = request.json_body
    token = request.headers['X-Request-Token']
    return {'order': order['id'], 'token': token}


@app.route('/keys', api_key_required=True)
def keys():
    return []


@app.route('/open', authorizer=None)
def open_route():
    # Chalice's query_params is None without a query string.
    params = app.current_request.query_params or {}
    return {'page': params.get('page')}


@app.lambda_function()
def worker(event, context):
    return {}


@app.schedule('rate(1 hour)')
def every_hour(event):
    pass
