# A Blueprint subclass keeps Quart's constructor, so the url_prefix passed to
# it still prefixes every route registered on the instance.
from quart import Blueprint, Quart


class ApiBlueprint(Blueprint):
    pass


items = ApiBlueprint("items", __name__, url_prefix="/items")


@items.route("/list")
async def list_items():
    return ""


app = Quart(__name__)
app.register_blueprint(items)
