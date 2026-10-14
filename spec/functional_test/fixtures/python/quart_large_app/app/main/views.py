from . import main


@main.route("/")
async def index():
    return "x"
