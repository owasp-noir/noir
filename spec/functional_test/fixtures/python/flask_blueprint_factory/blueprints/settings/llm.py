from flask import Blueprint


def construct_blueprint(datastore):
    llm_blueprint = Blueprint("llm", __name__)

    @llm_blueprint.route("/models")
    def models():
        return ""

    return llm_blueprint
