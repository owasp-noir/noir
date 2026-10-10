from fasthtml.common import *
from starlette.responses import RedirectResponse

app, rt = fast_app()


def login_required(f):
    return f


@rt("/")
def get():
    return Titled("Hello")


@rt("/todos/{tid}")
def delete(tid: int):
    return ""


@app.post("/login")
def login(username: str, password: str):
    return RedirectResponse("/", status_code=303)


@rt
def profile(req, session):
    return ""


@rt
def post():
    return ""


@rt("/search")
@login_required
def search(q: str, request: Request):
    return ""


@app.route("/items/{item_id:int}")
async def put(item_id: int, name: str):
    return ""


@rt("/upload", methods=["post"])
def upload(file: UploadFile):
    return ""
