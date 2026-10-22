from rest_framework.routers import DefaultRouter


class BulkRouter(DefaultRouter):
    """Project-wide router subclass, imported by every app's api/urls.py.

    Subclassing DefaultRouter to widen the list route's method mapping is the
    normal way a REST project adds bulk operations.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.routes[0].mapping.update({
            'put': 'bulk_update',
            'delete': 'bulk_destroy',
        })
