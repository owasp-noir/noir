from flask import Blueprint
from flask_allows import Allows as Perms
from flask_allows import requires as allows_requires

from other.scopes import requires

bp = Blueprint("scoped", __name__)
perms = Perms()


def is_admin(user):
    return user.is_admin


@bp.route("/scoped")
@requires("read:public")
def scoped():
    return "scoped"


@bp.route("/perms")
@perms.requires(is_admin)
def perms_view():
    return "perms"


@bp.route("/both")
@allows_requires(is_admin)
def both():
    return "both"
