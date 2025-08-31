import sys
import json
import hashlib
from sanic import Sanic, response
from sanic.request import Request

app = Sanic("test_app")
app.config.SECRET = "dd2e7b987b357908fac0118ecdf0d3d2cae7b5a635f802d6"

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

if __name__ == "__main__":
    port = 80
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    
    app.run(host='0.0.0.0', port=port)