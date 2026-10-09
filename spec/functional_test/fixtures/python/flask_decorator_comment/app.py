from flask import Flask, request

app = Flask(__name__)


@app.route("/a")  # old (remove
def a():
    return request.args.get("qa")


@app.route(
    "/b",
    methods=["POST"],  # see (docs
)
def b():
    return request.form.get("qb")
