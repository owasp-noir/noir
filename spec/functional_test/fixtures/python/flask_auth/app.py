from flask import Flask, jsonify
from flask_login import login_required
from flask_jwt_extended import jwt_required

app = Flask(__name__)


@app.route('/public')
def public_page():
    return jsonify(message="public")


@login_required
@app.route('/profile')
def profile():
    return jsonify(user="profile")


@jwt_required()
@app.route('/api/data')
def api_data():
    return jsonify(data=[])


@app.route('/open')
def open_page():
    return jsonify(message="open")
