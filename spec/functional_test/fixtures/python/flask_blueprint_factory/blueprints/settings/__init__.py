from flask import Blueprint

from blueprints.settings.llm import construct_blueprint as construct_llm


def construct_blueprint(datastore):
    settings_blueprint = Blueprint("settings", __name__)
    settings_blueprint.register_blueprint(construct_llm(datastore), url_prefix="/ai")

    @settings_blueprint.route("/general")
    def general():
        return ""

    return settings_blueprint
