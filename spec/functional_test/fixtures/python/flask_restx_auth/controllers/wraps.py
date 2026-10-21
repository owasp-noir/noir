from functools import wraps

from flask import abort, current_app, request
from werkzeug.exceptions import Unauthorized

SIGNUP_ENABLED = True
INNER_KEY = "change-me"


def session_required(view):
    """Answers through the login manager, never raising itself."""

    @wraps(view)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated:
            return current_app.login_manager.unauthorized()
        return view(*args, **kwargs)

    return decorated


def signup_enabled(view):
    """A feature gate: 403 on a flag, whoever the caller is."""

    @wraps(view)
    def decorated(*args, **kwargs):
        if not SIGNUP_ENABLED:
            abort(403)
        return view(*args, **kwargs)

    return decorated


def _bearer_token():
    token = request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not token:
        raise Unauthorized("missing token")
    return token


def token_required(view=None, *, scope=None):
    def decorator(fn):
        @wraps(fn)
        def decorated(*args, **kwargs):
            _bearer_token()
            return fn(*args, **kwargs)

        return decorated

    if view:
        return decorator(view)
    return decorator


def inner_key_only(view):
    @wraps(view)
    def decorated(*args, **kwargs):
        if request.headers.get("X-Inner-Key") != INNER_KEY:
            abort(404)
        return view(*args, **kwargs)

    return decorated


def admission(*, signup=False):
    def decorator(view):
        admitted = view
        if signup:
            admitted = signup_enabled(admitted)
        return session_required(admitted)

    return decorator
