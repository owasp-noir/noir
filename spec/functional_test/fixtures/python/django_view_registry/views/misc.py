from django.contrib.auth.forms import AuthenticationForm
from django.views.generic import View

from core.views import ConditionalLoginRequiredMixin


class LoginView(View):
    def next_url(self, request):
        data = request.POST if request.method == "POST" else request.GET
        return data.get("next")

    def get(self, request):
        return self.next_url(request)

    def post(self, request):
        form = AuthenticationForm(request, data=request.POST)
        return self.next_url(request)


class MediaView(ConditionalLoginRequiredMixin, View):
    def get(self, request, path):
        return path
