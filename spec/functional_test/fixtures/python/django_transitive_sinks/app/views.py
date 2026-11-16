from django.http import HttpResponse
from . import services
from .services import build_report, normalize, ping_a, call_ambiguous


def export(request):
    return HttpResponse(services.run_export(request.POST.get("target")))


def report(request):
    return HttpResponse(build_report(request.GET.get("name")))


def ambiguous(request):
    return HttpResponse(call_ambiguous(request.GET.get("q")))


def cycle(request):
    return HttpResponse(ping_a(3))


def ping(request):
    return HttpResponse(normalize(request.GET.get("q")))
