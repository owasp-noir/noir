from flask import Flask
from blueprints.auth import auth_bp
from blueprints.items import items_bp

app = Flask(__name__)
app.register_blueprint(auth_bp, url_prefix='/api/v1')
app.register_blueprint(items_bp, url_prefix='/api/v2')

if __name__ == "__main__":
    app.run()
