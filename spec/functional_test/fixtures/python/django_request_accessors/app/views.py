from django.http import JsonResponse


def headers(request):
    token = request.headers.get("X-Api-Token")
    forwarded = request.META["HTTP_X_FORWARDED_FOR"]
    ctype = request.META.get("CONTENT_TYPE")
    remote = request.META.get("REMOTE_ADDR")
    return JsonResponse({})


def upload(request):
    document = request.FILES["document"]
    return JsonResponse({})
