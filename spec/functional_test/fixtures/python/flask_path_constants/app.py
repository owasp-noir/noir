from flask import Blueprint, Flask

app = Flask(__name__)

API = "/api"
DOWNLOAD_PATH = "/download/<path:filename>"
REPORTS = API + "/reports"

MODE = "/a"
MODE = "/b"

files = Blueprint("files", __name__, url_prefix=API + "/files")


@files.route(DOWNLOAD_PATH)
def download(filename):
    return filename


@app.route(f"{REPORTS}/<int:year>")
def report(year):
    return str(year)


@app.get(API + "/ping")
def ping():
    return "pong"


@app.post("/hooks" "/github")
def github_hook():
    return "", 204


@app.route(MODE)
def rebound():
    return "which one"


def register_tenant_routes(tenant):
    @app.route(f"{API}/tenants/{tenant}")
    def tenant_home():
        return tenant


app.register_blueprint(files)
