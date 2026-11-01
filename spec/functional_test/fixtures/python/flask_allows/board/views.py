from flask import Flask
from flask.views import MethodView
import flask_allows as fa
from flask_allows import (
    ForRequest,
    Not,
    requires,
)
from flask_allows import requires as perm_req

from board.extensions import allows
from other.perms import allows as buckets

app = Flask(__name__)


def is_admin(user):
    return user.is_admin


def is_banned(user):
    return user.banned


class Settings(MethodView):
    decorators = [
        allows.requires(
            is_admin,
            on_fail=lambda: "no",
        )
    ]

    def get(self):
        return "settings"

    def post(self):
        return "saved"


def can_view(board):
    return lambda user: board.public or user.is_member(board)


def load_board():
    return None


class Board(MethodView):
    decorators = [allows.requires(ForRequest(can_view, load_board), on_fail=lambda: "no")]

    def get(self):
        return "board"


class Overview(MethodView):
    def get(self):
        return "overview"


app.add_url_rule("/admin/settings", view_func=Settings.as_view("settings"))
app.add_url_rule("/overview", view_func=Overview.as_view("overview"))
app.add_url_rule("/board", view_func=Board.as_view("board"))


@app.route("/admin/purge", methods=["POST"])
@requires(is_admin)
def purge():
    return "purged"


@app.route("/guests-only")
@allows.requires(Not(is_admin))
def guests_only():
    return "hello guest"


@app.route("/bucketed")
@buckets.requires("search")
def bucketed():
    return "results"


@app.route("/not-banned-admin")
@allows.requires(Not(is_banned), is_admin)
def not_banned_admin():
    return "admin, not banned"


@app.route("/aliased")
@perm_req(is_admin)
def aliased():
    return "aliased"


@app.route("/module")
@fa.requires(is_admin)
def module():
    return "module"
