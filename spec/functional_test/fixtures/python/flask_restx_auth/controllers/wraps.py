from functools import wraps

from flask import abort, current_app, redirect, request, session, url_for
from werkzeug.exceptions import Forbidden, Unauthorized

from controllers.models import Member

SIGNUP_ENABLED = True
INNER_KEY = "change-me"
SETTINGS = {"visibility": "public"}


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
            # Finding the owner by role checks nothing about the caller.
            owner = Member.query.filter(Member.role == "owner").first()
            if owner is None:
                raise Forbidden("workspace has no owner")
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


def admin_only(view):
    @wraps(view)
    def decorated(*args, **kwargs):
        if not current_user.is_admin:
            raise Forbidden()
        return view(*args, **kwargs)

    return decorated


def admission(*, signup=False, roles=None):
    def decorator(view):
        @wraps(view)
        def check_roles(*args, **kwargs):
            if roles is not None and current_user.role not in roles:
                raise Forbidden()
            return view(*args, **kwargs)

        admitted = check_roles
        if signup:
            admitted = signup_enabled(admitted)
        return session_required(admitted)

    return decorator


def authed():
    return bool(session.get("id"))


def is_admin():
    return authed() and session.get("type") == "admin"


def get_setting(key):
    return SETTINGS.get(key)


def event_running():
    return get_setting("running")


def members_only(view):
    """The view runs only for a logged-in caller; others go to the login page."""

    @wraps(view)
    def decorated(*args, **kwargs):
        if authed():
            return view(*args, **kwargs)
        return redirect(url_for("auth.login"))

    return decorated


def admins_only(view):
    @wraps(view)
    def decorated(*args, **kwargs):
        if is_admin():
            return view(*args, **kwargs)
        abort(403)

    return decorated


def visibility_gate(view):
    """Open when the deployment's setting is public: no guard to report."""

    @wraps(view)
    def decorated(*args, **kwargs):
        mode = get_setting("visibility")
        if mode == "public":
            return view(*args, **kwargs)
        if not authed():
            abort(403)
        return view(*args, **kwargs)

    return decorated


def during_event(view):
    """A time window with an admin bypass: anyone gets in while it runs."""

    @wraps(view)
    def decorated(*args, **kwargs):
        if event_running() or current_user.is_admin:
            return view(*args, **kwargs)
        abort(403)

    return decorated
