# A Blueprint subclass keeps Flask's constructor, so the url_prefix passed
# to it still prefixes every route registered on the instance.
from flask import Blueprint, Flask


class EventBlueprint(Blueprint):
    pass


events = EventBlueprint("events", __name__, url_prefix="/event/<int:event_id>")


@events.route("/manage")
def manage(event_id):
    return ""


def registration(event_id):
    return ""


events.add_url_rule("/registration/", "registration", registration)

app = Flask(__name__)
app.register_blueprint(events)
