from django.http import JsonResponse


def profile(request):
    return JsonResponse({"user": None})


def tokens(request):
    return JsonResponse({"tokens": []})


def token_detail(request, pk):
    return JsonResponse({"id": str(pk)})
