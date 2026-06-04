from flask import Flask, request

app = Flask(__name__)


@app.route("/flask-home", methods=["GET"])
def home():
    q = request.args.get("q")
    return {"q": q}
