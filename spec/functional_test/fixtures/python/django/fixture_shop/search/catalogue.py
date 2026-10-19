from django.http import HttpResponse
from django.views.generic import View


class BrowseView(View):
    def get(self, request):
        return HttpResponse(request.GET.get("sort"))
