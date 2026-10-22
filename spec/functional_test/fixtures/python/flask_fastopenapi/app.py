from flask import Flask

from extensions import ext_fastopenapi

app = Flask(__name__)
ext_fastopenapi.init_app(app)


@app.route("/health")
def health():
    return "ok"
