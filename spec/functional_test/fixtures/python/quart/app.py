from quart import Quart, Blueprint, request, websocket, jsonify
from quart.views import MethodView, View
import external_views

app = Quart(__name__)
api = Blueprint("api", __name__, url_prefix="/api/v1")
parent_bp = Blueprint("parent", __name__)
nested_bp = Blueprint("nested", __name__)


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


@nested_bp.get("/reports/<int:report_id>")
async def nested_report(report_id):
    mode = request.args.get("mode")
    return jsonify({"report_id": report_id, "mode": mode})


async def registered_search():
    term = request.args.get("term")
    trace_id = request.headers.get("X-Trace-Id")
    return jsonify({"term": term, "trace_id": trace_id})


async def registered_create():
    body = await request.get_json()
    return jsonify({"name": body["name"]})


class ReportView(MethodView):
    async def get(self, report_id):
        include = request.args.get("include")
        return jsonify({"id": report_id, "include": include})

    async def post(self):
        body = await request.get_json()
        return jsonify({"title": body["title"]})


class DispatchReportView(View):
    methods = [
        "GET",
        "POST",
    ]

    async def dispatch_request(self):
        if request.method == "POST":
            body = await request.get_json()
            return jsonify({"name": body["name"]})

        owner = request.args.get("owner")
        return jsonify({"owner": owner})


@app.route("/sync-update", methods=["POST"])
async def sync_update():
    body = await request.get_json()
    # field access and json-variable access on the SAME line — locks the
    # once-per-line json fallback in extract_request_params
    page = request.args["page"] if body["name"] else None
    return {"page": page}


@app.websocket("/ws")
async def ws():
    while True:
        data = await websocket.receive()
        await websocket.send(data)


app.register_blueprint(api)
parent_bp.register_blueprint(nested_bp, url_prefix="/child")
app.register_blueprint(parent_bp, url_prefix="/mounted")
app.add_url_rule("/reports/<int:report_id>", view_func=ReportView.as_view("report_detail"), methods=["GET"])
app.add_url_rule("/reports", view_func=ReportView.as_view("report_create"), methods=["POST"])
app.add_url_rule("/dispatch-reports", view_func=DispatchReportView.as_view("dispatch_reports"))
api.add_url_rule("/registered-search", "registered_search", registered_search, methods=["GET"])
api.add_url_rule(rule="/registered-create", endpoint="registered_create", view_func=registered_create, methods=["POST"])
api.add_url_rule("/external-search", view_func=external_views.external_search, methods=["GET"])


if __name__ == "__main__":
    app.run()
