from rest_framework import mixins, viewsets


class ArticleViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    queryset = Article.objects.all()

    def get_queryset(self):
        queryset = self.queryset
        author = self.request.query_params.get('author', None)
        if author is not None:
            queryset = queryset.filter(author=author)
        return queryset

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset())
        return self.get_paginated_response(page)


class TagViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin,
                 mixins.CreateModelMixin, viewsets.GenericViewSet):
    queryset = Article.objects.all()

    def get_queryset(self):
        tag = self.request.query_params.get('tag')
        return self.queryset.filter(tag=tag)


class StatusViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    queryset = Article.objects.all()

    def get_queryset(self):
        return self.queryset.filter(status=self.request.query_params['status'])

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        return response
