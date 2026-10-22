from flask import Flask

from controllers.console import bp as console_bp
from controllers.service_api import bp as service_api_bp

app = Flask(__name__)
app.register_blueprint(console_bp)
app.register_blueprint(service_api_bp)
