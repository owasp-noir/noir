from bottle import Bottle, route

app = Bottle()


# A list of paths serves the handler at each of them.
@app.route(["/multi/a", "/multi/b"])
def multi():
    return "multi"


@route(["/bare/a", "/bare/b"], method="POST")
def bare_multi():
    return "bare"


def positional_handler():
    return "positional"


# route(path, method, callback) positionally.
app.route("/positional", "DELETE", positional_handler)
