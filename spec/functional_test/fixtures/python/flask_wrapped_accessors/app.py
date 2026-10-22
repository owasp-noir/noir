from flask import Flask, request
app = Flask(__name__)

@app.route("/one")
def one():
    a = request.args.get("q1")
    b = request.form["f1"]
    c = request.headers.get("H1")
    return a

@app.route("/split", methods=["GET", "POST"])
def split():
    a = request.args.get(
        "q2"
    )
    b = request.form[
        "f2"
    ]
    c = request.headers.get(
        "H2", None
    )
    d = request.cookies.get(
        'c2')
    # x = request.args.get(
    #     "commented")
    return a
