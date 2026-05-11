from bottle import route, request, response
from helpers import build_report


@route("/report", method="GET")
def report():
    user_id = request.query.get("user_id")
    data = build_report(user_id)
    response.content_type = "application/json"
    return data


@route("/ping", method="GET")
def ping():
    return {"pong": True}
