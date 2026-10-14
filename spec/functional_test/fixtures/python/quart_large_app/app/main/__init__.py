from quart import Blueprint

main = Blueprint("main", __name__, url_prefix="/own")

from . import views
