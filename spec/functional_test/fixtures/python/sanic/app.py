import sys
import json
import hashlib
import external_handlers
from sanic import Blueprint, Sanic, response
from sanic.request import Request
from sanic.views import HTTPMethodView

app = Sanic("test_app")
app.config.SECRET = "dd2e7b987b357908fac0118ecdf0d3d2cae7b5a635f802d6"
reports_bp = Blueprint("reports", url_prefix="/reports")

@app.route('/sign', methods=['GET', 'POST'])
async def sign_sample(request: Request):
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        # Handle user creation logic here
        return response.html('<html><body>Login page</body></html>')
    
    return response.html('<html><body>Sign page</body></html>')

@app.route('/cookie', methods=['GET'])
async def cookie_test(request: Request):
    if request.cookies.get('test') == "y":
        return response.text("exist cookie")
    
    return response.text("no cookie")

@app.route('/login', methods=['POST'])
async def login_sample(request: Request):
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        # Handle login logic here
        return response.html('<html><body>Index page</body></html>')
    
    return response.html('<html><body>Login page</body></html>')

@app.route('/create_record', methods=['PUT'])
async def create_record(request: Request):
    name = request.form['name']
    record = {'name': name}
    # Handle record creation
    return response.json(record)

@app.route('/delete_record', methods=['DELETE'])
async def delete_record(request: Request):
    record = request.json
    # Handle record deletion using the name field
    name = record['name']
    return response.json(record)

@app.route('/get_ip', methods=['GET'])
async def get_ip(request: Request):
    data = {'ip': request.headers.get('X-Forwarded-For', request.ip)}
    return response.json(data)

@app.route('/')
async def index(request: Request):
    return response.html('<html><body>Index page</body></html>')

@app.websocket('/feed/<channel>')
async def feed_socket(request: Request, ws, channel: str):
    token = request.args.get('token')
    await ws.send(json.dumps({'channel': channel, 'token': token}))

@reports_bp.get('/<report_id:int>')
async def get_report(request: Request, report_id: int):
    include = request.args.get('include')
    return response.json({'id': report_id, 'include': include})

@reports_bp.post('/create')
async def create_report(request: Request):
    record = request.json
    title = record.get('title')
    return response.json({'title': title})


async def update_report(request: Request, report_id: int):
    record = request.json
    status = record.get('status')
    return response.json({'id': report_id, 'status': status})


async def audit_reports(request: Request):
    actor = request.args.get('actor')
    return response.json({'actor': actor})


class ReportMethodView(HTTPMethodView):
    async def get(self, request: Request, report_id: int):
        include = request.args.get('include')
        return response.json({'id': report_id, 'include': include})

    async def post(self, request: Request, report_id: int):
        record = request.json
        title = record.get('title')
        return response.json({'id': report_id, 'title': title})


app.add_route(
    update_report,
    '/reports/<report_id:int>/status',
    methods=['PATCH'],
)
app.add_route(
    ReportMethodView.as_view(),
    '/class-reports/<report_id:int>',
)
app.add_route(
    external_handlers.external_status,
    '/external/<item_id:int>',
    methods=['PUT'],
)
reports_bp.add_route(
    handler=audit_reports,
    uri='/audit',
    methods=['GET'],
)
app.static('/assets', './static')
reports_bp.static('/files', './report_files')
app.blueprint(reports_bp, url_prefix="/api/v1")

if __name__ == "__main__":
    port = 80
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    
    app.run(host='0.0.0.0', port=port)
