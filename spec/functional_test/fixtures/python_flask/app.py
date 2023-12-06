import sys
import json
import hashlib
from flask import Flask, render_template, request, session, jsonify
from database import db_session 
from models import User
from utils import get_hash

app = Flask(__name__)
app.secret_key = "dd2e7b987b357908fac0118ecdf0d3d2cae7b5a635f802d6" # random generate

@app.teardown_appcontext
def shutdown_session(exception=None):
    db_session.remove()

@app.route('/sign', methods=['GET', 'POST'])
def sign_sample():
    if request.method == 'POST':
        username = request.form['username']
        password = get_hash(request.form['password'], app.secret_key)
        if User.query.filter(User.name == username).first():
            return render_template('error.html')

        u = User(username, password)
        db_session.add(u)
        db_session.commit()
        return render_template('login.html')

    return render_template('sign.html')

@app.route('/cookie', methods=['GET'])
def cookie_test():
    if request.cookies.get('test') == "y":
        return "exist cookie"

    return "no cookie"

@app.route('/login', methods=['POST'])
def login_sample():
    if request.method == 'POST':
        username = request.form['username']
        password = get_hash(request.form['password'], app.secret_key)
        if User.query.filter(User.name == username and User.password == password).first():
            session['logged_in'] = True
            session['username'] = username
            return render_template('index.html')
        else:
            return "Fail"

    return render_template('login.html')

@app.route('/create_record', methods=['PUT'])
def create_record():
    record = json.loads(request.data)
    with open('/tmp/data.txt', 'r') as f:
        data = f.read()
    if not data:
        records = [record]
    else:
        records = json.loads(data)
        records.append(record)
    with open('/tmp/data.txt', 'w') as f:
        f.write(json.dumps(records, indent=2))
    return jsonify(record)

@app.route('/delete_record', methods=['DELETE'])
def delte_record():
    record = json.loads(request.data)
    new_records = []
    with open('/tmp/data.txt', 'r') as f:
        data = f.read()
        records = json.loads(data)
        for r in records:
            if r['name'] == record['name']:
                continue
            new_records.append(r)
    with open('/tmp/data.txt', 'w') as f:
        f.write(json.dumps(new_records, indent=2))
    return jsonify(record)

@app.route('/get_ip', methods=['GET'])
def json_sample():
    data = {'ip': request.headers.get('X-Forwarded-For', request.remote_addr)}

    return jsonify(data), 200

@app.route('/')
def index():
    return render_template('index.html')


if __name__ == "__main__":
    port = 80
    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    app.run(host='0.0.0.0', port=port)

