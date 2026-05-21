from quart import Quart, Blueprint, request, websocket, jsonify

app = Quart(__name__)
api = Blueprint("api", __name__, url_prefix="/api/v1")


@app.route("/items", methods=["GET", "POST"])
async def items():
    if request.method == "POST":
        body = await request.get_json()
        name = body["name"]
        return jsonify({"name": name})
    q = request.args.get("q")
    return jsonify({"q": q})


@app.get("/healthz")
async def healthz():
    return "ok"


@app.delete("/items/<int:item_id>")
async def delete_item(item_id):
    return ("", 204)


@api.post("/users")
async def create_user():
    body = await request.get_json()
    return jsonify({"username": body["username"]})


@app.websocket("/ws")
async def ws():
    while True:
        data = await websocket.receive()
        await websocket.send(data)


app.register_blueprint(api)


if __name__ == "__main__":
    app.run()
