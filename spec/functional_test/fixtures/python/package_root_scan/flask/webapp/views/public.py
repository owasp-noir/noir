from flask import request
from webapp import app


@app.route("/health")
def health():
    verbose = request.args.get("verbose")
    return "ok"
