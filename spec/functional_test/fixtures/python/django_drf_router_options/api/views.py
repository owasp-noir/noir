from rest_framework import viewsets


class TagViewSet(viewsets.ModelViewSet):
    # View.dispatch rejects PUT/PATCH/DELETE despite the ModelViewSet base.
    http_method_names = ["get", "post"]
