from sanic import Sanic
from sanic.response import json
from db import save_user, audit_log

app = Sanic("App")


@app.route("/users", methods=["POST"])
async def create_user(request):
    name = request.form.get("name")
    user = save_user(name)
    audit_log(user)
    return json({"id": user})


@app.route("/healthz", methods=["GET"])
async def healthz(request):
    return json({"ok": True})
