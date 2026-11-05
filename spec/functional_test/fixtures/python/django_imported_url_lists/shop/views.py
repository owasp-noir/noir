from django.http import HttpResponse


def health(request):
    return HttpResponse("ok")


def orders(request):
    return HttpResponse("")


def event(request, organizer):
    return HttpResponse("")


def event_index(request, organizer, event):
    return HttpResponse("")


def organizer_index(request, organizer):
    return HttpResponse("")


def locale_set(request):
    return HttpResponse("")
