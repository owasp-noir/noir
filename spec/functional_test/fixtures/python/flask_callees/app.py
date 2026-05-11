from flask import Flask, jsonify, request
from helpers import build_user_query, run_sql_query, notify_admin, log_audit

app = Flask(__name__)


@app.route('/users', methods=['POST'])
def create_user():
    name = request.form['name']
    query = build_user_query(name)
    user = run_sql_query(query)
    log_audit(user)
    notify_admin(user)
    return jsonify(user)


@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    sql = build_user_query(order_id)
    order = run_sql_query(sql)
    return jsonify(order)


@app.route('/healthz', methods=['GET'])
def healthz():
    return jsonify({"ok": True})
