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


def channel_hook(request, channel_slug, plugin_id):
    return HttpResponse()


def thumbnail(request, instance_id, size, format=None):
    return HttpResponse()


def image(request, instance_id):
    return HttpResponse()
