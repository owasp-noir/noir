from quart import request
from . import auth


@auth.route("/login", methods=["POST"])
async def login():
    form = await request.form
    return "x"
