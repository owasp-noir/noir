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


# Handler with 12 unique callees — exercises Callee::MAX_PER_ENDPOINT.
# The endpoint should emit exactly 10 callees, dropping the last two
# (a, b) in source order.
@app.route('/many', methods=['GET'])
def many():
    c1()
    c2()
    c3()
    c4()
    c5()
    c6()
    c7()
    c8()
    c9()
    c10()
    a()
    b()
    return jsonify({"ok": True})
