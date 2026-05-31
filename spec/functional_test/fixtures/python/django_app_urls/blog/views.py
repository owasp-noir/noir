from django.http import JsonResponse


def posts(request):
    return JsonResponse({"posts": []})


def dashboard(request):
    return JsonResponse({"ok": True})
