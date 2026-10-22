from flask import Flask

app = Flask(__name__)


# Werkzeug converters can take arguments. The argument list is part of the
# converter, not of the parameter name.
@app.route("/n/<int(signed=True):num>")
def signed_number(num):
    return str(num)


@app.route("/k/<any(about, help):page>")
def any_page(page):
    return page


@app.route("/files/<path:subpath>")
def files(subpath):
    return subpath
