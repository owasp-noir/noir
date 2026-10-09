from django.http import HttpResponse


def home(request):
    return HttpResponse()


def about(request):
    return HttpResponse()


def item(request, pk):
    return HttpResponse(pk)


def users(request):
    return HttpResponse()


def teams(request):
    return HttpResponse()


def ping(request):
    return HttpResponse()
