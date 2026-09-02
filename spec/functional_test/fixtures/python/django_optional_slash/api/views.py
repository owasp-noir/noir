from django.http import HttpResponse


def tags(request):
    return HttpResponse()


def search(request):
    q = request.GET.get('q')
    return HttpResponse(q)


def comments(request, slug):
    return HttpResponse(slug)


def feed(request, page=None):
    return HttpResponse()
