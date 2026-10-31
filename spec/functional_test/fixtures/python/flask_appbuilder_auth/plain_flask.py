from flask import Flask
from internal_lib.perm import has_access

plain = Flask(__name__)


@plain.route("/plain/has-access")
@has_access
def plain_has_access():
    return "x"
