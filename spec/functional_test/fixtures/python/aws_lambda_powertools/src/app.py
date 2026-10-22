from aws_lambda_powertools import Logger
from aws_lambda_powertools.event_handler import APIGatewayRestResolver
from aws_lambda_powertools.event_handler.api_gateway import Router

from routes import orders
from routes.health import router as health_router

logger = Logger()
app = APIGatewayRestResolver()
router = Router()
API_VERSION = "v1"
v2 = Router()


@app.get("/todos")
def get_todos():
    status = app.current_event.get_query_string_value(name="status", default_value="open")
    # legacy = app.current_event.headers["X-Legacy"]
    return {"todos": [], "status": status}


@app.post("/todos/<todo_id>")
def update(todo_id: str):
    body = app.current_event.json_body
    return {"id": todo_id, "body": body}


@app.route("/search", method=["GET", "POST"])
def search():
    event = app.current_event
    term = event.query_string_parameters.get("term")
    trace_id = event.headers["X-Trace-Id"]
    return {"term": term, "trace": trace_id}


@router.delete("/admin/users/<uid>")
def delete_user(uid):
    return {}


@app.route("/legacy", "POST")
def legacy():
    return {}


@app.route("/bulk", ["PUT", "PATCH"])
def bulk():
    return {}


@v2.get("/")
def v2_index():
    return {}


@app.not_found
def not_found(ex):
    return {"message": "not found"}


app.include_router(router, prefix=f"/{API_VERSION}")
app.include_router(orders.router, prefix="/orders")
app.include_router(health_router, prefix=os.environ.get("HEALTH_PREFIX", ""))
app.include_router(v2, "/v2")
# app.include_router(orders.router, prefix="/old")


@logger.inject_lambda_context
def lambda_handler(event, context):
    return app.resolve(event, context)
