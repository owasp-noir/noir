from django.http import HttpResponse


def search(request):
    # request.GET is a QueryDict; getlist reads repeated keys (?tags=a&tags=b).
    tags = request.GET.getlist('tags')
    q = request.GET.get('q')
    # Negative: a dynamic key must not be reported.
    dynamic = request.GET.get(some_key)
    return HttpResponse(q)
