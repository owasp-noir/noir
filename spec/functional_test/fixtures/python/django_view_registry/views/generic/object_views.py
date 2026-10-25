from django.views.generic import View

from core.views import ConditionalLoginRequiredMixin


class ReturnURLMixin:
    def get_return_url(self, request):
        return request.GET.get("return_url")


class ObjectListView(ConditionalLoginRequiredMixin, View):
    def get(self, request):
        return request.GET.get("per_page")


class ObjectView(ConditionalLoginRequiredMixin, View):
    def get(self, request, **kwargs):
        return kwargs


class ObjectEditView(ReturnURLMixin, ConditionalLoginRequiredMixin, View):
    form = None

    def get(self, request, **kwargs):
        return kwargs

    def post(self, request, **kwargs):
        form = self.form(data=request.POST)
        return self.get_return_url(request)
