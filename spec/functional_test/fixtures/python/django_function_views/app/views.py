import json

from pydantic import BaseModel

from app import forms
from app.forms import LoginForm


class Spec(BaseModel):
    name: str | None = None
    tags: str | None = None


def login(request):
    form = LoginForm()
    if request.method == "POST":
        form = LoginForm(request.POST)
    closed = "account-closed" in request.GET
    return render(request, "login.html", {"form": form, "closed": closed})


def ping(request, code, action="success"):
    headers = request.META
    ua = headers.get("HTTP_USER_AGENT", headers["REMOTE_ADDR"])
    body = request.body
    return HttpResponse("OK")


def ping_by_slug(request, slug):
    return ping(request, slug)


def create_check(request):
    spec = Spec.model_validate(json.loads(request.body))
    return JsonResponse({"name": spec.name})


def list_checks(request):
    tag = request.GET.get("tag")
    return JsonResponse({"tag": tag})


def checks(request):
    if request.method == "POST":
        return create_check(request)
    return list_checks(request)


def search(request):
    form = forms.SearchForm(request.GET)
    return render(request, "search.html", {"form": form})
