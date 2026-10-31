import functools

from flask_appbuilder.security.sqla.manager import security_manager
from flask_jwt_extended import verify_jwt_in_request
from flask_jwt_extended.exceptions import NoAuthorizationError
from flask_login import current_user


def api_errors(f):
    """Turns errors the view raises into JSON; refuses nobody itself."""

    def wraps(self, *args, **kwargs):
        try:
            return f(self, *args, **kwargs)
        except NoAuthorizationError:
            return json_error_response("no authorization", status=401)

    return functools.update_wrapper(wraps, f)


def read_gate(function):
    @functools.wraps(function)
    def wrapped(self, *args, **kwargs):
        if not current_user.is_authenticated:
            verify_jwt_in_request()
        if security_manager.has_access("can_read", "Chart"):
            return function(self, *args, **kwargs)
        return self.response_403()

    return wrapped


def maybe_user(function):
    @functools.wraps(function)
    def wrapped(self, *args, **kwargs):
        verify_jwt_in_request(optional=True)
        return function(self, *args, **kwargs)

    return wrapped


def json_error_response(message, status=500):
    return {"message": message}, status


def is_feature_enabled(name):
    return True


def get_user_id():
    return getattr(current_user, "id", None)


def redirect_to_login():
    return {"redirect": "/login/"}, 302


def jwt_positional(function):
    @functools.wraps(function)
    def wrapped(*args, **kwargs):
        verify_jwt_in_request(True)
        return function(*args, **kwargs)

    return wrapped
