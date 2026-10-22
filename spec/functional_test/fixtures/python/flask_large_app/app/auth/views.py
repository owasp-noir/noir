from flask import request
from . import auth


@auth.route("/login", methods=["POST"])
def login():
    email = request.form.get("email")
    return "x"
