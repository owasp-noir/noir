from flask import Flask, request

app = Flask(__name__)


@app.route("/users/action", methods=["POST"])
def user_action():
    data = request.form
    return "{} {}".format(data["first_name"], data.get("last_name"))


@app.route("/users/direct", methods=["POST"])
def user_direct():
    return request.form["first_name"]


@app.route("/search")
def search():
    args = request.args.to_dict()
    page = request.args.get("page")
    return "{} {} {}".format(args["q"], args.get("sort"), page)


@app.route("/single", methods=["POST"])
def single():
    name = request.form.get("name")
    return name.get("ignored") if name else ""
