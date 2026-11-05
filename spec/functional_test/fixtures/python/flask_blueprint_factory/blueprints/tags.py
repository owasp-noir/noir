from flask import Blueprint

# Not returned by the factory, so not under its prefix.
helper_bp = Blueprint("helper", __name__)


@helper_bp.route("/h")
def helper():
    return ""


def construct_blueprint(datastore):
    tags_blueprint = Blueprint("tags", __name__)

    @tags_blueprint.route("/list")
    def tags_list():
        return ""

# A comment at column 0 inside the factory does not end it.

    return tags_blueprint
