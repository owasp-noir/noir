import functools

from flask import Flask, abort, request, session

app = Flask(__name__)


def get_config(key):
    return app.config.get(key)


def is_setup():
    return bool(get_config("setup")) is True


def authed():
    return bool(session.get("id", False))


def is_admin():
    if authed():
        return session.get("type") == "admin"
    return False


def managers_only(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if is_setup() and not is_admin():
            abort(403)
        return f(*args, **kwargs)

    return wrapper


def nested_managers_only(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if is_setup():
            if not is_admin():
                abort(403)
        return f(*args, **kwargs)

    return wrapper


def admins_only(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if not is_admin():
            abort(403)
        return f(*args, **kwargs)

    return wrapper


def members_not_admins(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if authed() and not is_admin():
            abort(403)
        return f(*args, **kwargs)

    return wrapper


@app.route("/setup/git", methods=["DELETE"])
@managers_only
def disconnect():
    return "ok"


@app.route("/setup/nested", methods=["DELETE"])
@nested_managers_only
def nested():
    return "ok"


@app.route("/admin/thing", methods=["DELETE"])
@admins_only
def control():
    return "ok"


@app.route("/anyone", methods=["DELETE"])
@members_not_admins
def anyone():
    return "ok"


def admin_writes(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if request.method == "POST" and not is_admin():
            abort(403)
        return f(*args, **kwargs)

    return wrapper


def public_or_members(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        if get_config("visibility") == "public":
            pass
        elif not authed():
            abort(403)
        return f(*args, **kwargs)

    return wrapper


@app.route("/posts", methods=["GET", "POST"])
@admin_writes
def posts():
    return "ok"


@app.route("/scores")
@public_or_members
def scores():
    return "ok"
