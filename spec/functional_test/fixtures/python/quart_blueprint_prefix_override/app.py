# register_blueprint(url_prefix=...) replaces the blueprint's own url_prefix
# instead of being joined with it. Only when url_prefix is omitted (None)
# does the blueprint's own url_prefix apply.
from quart import Quart, Blueprint

override = Blueprint("override", __name__, url_prefix="/own")
parent = Blueprint("parent", __name__, url_prefix="/parent")
child = Blueprint("child", __name__, url_prefix="/child")
outer = Blueprint("outer", __name__, url_prefix="/outer")
inner = Blueprint("inner", __name__, url_prefix="/inner")
emptied = Blueprint("emptied", __name__, url_prefix="/gone")
kept = Blueprint("kept", __name__, url_prefix="/kept")
twice = Blueprint("twice", __name__)


@override.route("/o")
async def o():
    return ""


@child.route("/c")
async def c():
    return ""


@inner.route("/i")
async def i():
    return ""


@emptied.route("/e")
async def e():
    return ""


@kept.route("/k")
async def k():
    return ""


@twice.route("/t")
async def t():
    return ""


parent.register_blueprint(child)
outer.register_blueprint(inner, url_prefix="/mounted-inner")

app = Quart(__name__)
app.register_blueprint(override, url_prefix="/mounted")
app.register_blueprint(parent, url_prefix="/api")
app.register_blueprint(outer)
app.register_blueprint(emptied, url_prefix="")
app.register_blueprint(kept)
# Registered twice: served under both prefixes.
app.register_blueprint(twice, url_prefix="/v1")
app.register_blueprint(twice, url_prefix="/v2")
