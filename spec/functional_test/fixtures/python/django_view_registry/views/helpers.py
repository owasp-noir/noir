from django.views.generic import View


class FormBase(View):
    def extra(self, request):
        return request.POST.get("base_field")

    def post(self, request):
        return self.extra(request)


class FormOverride(FormBase):
    def extra(self, request):
        return request.POST.get("override_field")


class PingView(View):
    def get(self, request):
        return request.GET.get("from_helpers")
