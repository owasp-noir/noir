from django.http import HttpResponse
from django.views.generic import FormView, View


class BasketAddView(FormView):
    # `View.dispatch` answers 405 to anything else: no GET row.
    http_method_names = ["post"]

    def form_valid(self, form):
        return HttpResponse(self.request.POST.get("quantity"))


class PostOnlyView(View):
    http_method_names = ["post"]


class VoucherRemoveView(PostOnlyView):
    # The verb allowlist comes from the same-file base.
    def dispatch(self, request, *args, **kwargs):
        return HttpResponse(kwargs.get("pk"))
