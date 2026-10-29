from flask import Flask, redirect, request
from forms import LoginForm, ProfileForm, PlainForm, SearchForm

app = Flask(__name__)


@app.route("/login", methods=["GET", "POST"])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        if form.username.data == "a" and form.password.data == "b":
            return redirect("/")
    return "form"


@app.route("/profile", methods=["POST"])
def profile():
    form = ProfileForm()
    return form.bio.data


@app.route("/plain", methods=["POST"])
def plain():
    form = PlainForm()
    return "x"


@app.route("/unbound", methods=["POST"])
def unbound():
    form = SearchForm(obj=None, formdata=None)
    return "x"


@app.route("/search", methods=["POST"])
def search():
    form = SearchForm(request.args)
    return "x"
