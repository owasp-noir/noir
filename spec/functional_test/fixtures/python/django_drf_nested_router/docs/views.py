from rest_framework import mixins, viewsets


class ProjectViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    pass


class VersionViewSet(mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    lookup_field = "slug"


class BuildViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    pass
