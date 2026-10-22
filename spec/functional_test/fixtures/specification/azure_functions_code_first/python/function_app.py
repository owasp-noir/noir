import azure.functions as func

from blueprints import bp

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
app.register_functions(bp)


@app.route(route="hello", methods=["GET"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse("hello")


@app.function_name(name="CreateOrder")
@app.route(route="orders", methods=[func.HttpMethod.POST, func.HttpMethod.PUT],
           auth_level=func.AuthLevel.FUNCTION)
async def create_order(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(status_code=201)


# No route: the function name is the route. No methods: every verb.
@app.route()
@app.function_name("Status")
def status(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse("ok")


# @app.route(route="disabled")
@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer")
def cleanup(timer: func.TimerRequest) -> None:
    pass
