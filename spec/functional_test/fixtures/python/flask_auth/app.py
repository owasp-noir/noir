from flask import Flask, jsonify
from flask_login import login_required
from flask_jwt_extended import jwt_required

app = Flask(__name__)


@app.route('/public')
def public_page():
    return jsonify(message="public")


@app.route('/profile')
@login_required
def profile():
    return jsonify(user="profile")


@app.route('/api/data',
           methods=['GET'])
@jwt_required()
def api_data():
    return jsonify(data=[])


@app.route('/open')
def open_page():
    return jsonify(message="open")


# Flask registers the function the route decorator receives, so a
# decorator above it never wraps the registered view: this route is open.
@login_required
@app.route('/misordered')
def misordered():
    return jsonify(message="open")
