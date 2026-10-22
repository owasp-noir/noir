import azure.functions as func

bp = func.Blueprint()


@bp.route(route="items/{id}", methods=["get", "delete"])
def item(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(req.route_params.get("id"))
