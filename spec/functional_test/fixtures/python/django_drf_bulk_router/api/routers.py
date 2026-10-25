from rest_framework.routers import DefaultRouter


class BulkRouter(DefaultRouter):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.routes[0].mapping.update({
            "put": "bulk_update",
            "delete": "bulk_destroy",
        })
