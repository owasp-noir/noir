from flask import Flask
from webapp.views.admin import admin_bp

app = Flask(__name__)
app.register_blueprint(admin_bp, url_prefix="/admin")
