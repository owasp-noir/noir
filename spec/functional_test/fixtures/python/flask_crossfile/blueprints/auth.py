from flask import Blueprint, request, jsonify

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/login', methods=['POST'])
def login():
    username = request.form['username']
    password = request.form['password']
    return jsonify({"status": "ok"})

@auth_bp.route('/logout', methods=['GET'])
def logout():
    return jsonify({"status": "logged_out"})
