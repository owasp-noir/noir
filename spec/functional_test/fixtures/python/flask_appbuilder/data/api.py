from flask_appbuilder.api import expose

from app import DatabaseRestApi


class DatabaseDataRestApi(DatabaseRestApi):
    """resource_name is inherited from a base class in another file."""

    @expose("/<int:pk>/data", methods=("POST",))
    def data(self, pk):
        return {}
