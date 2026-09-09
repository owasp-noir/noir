from django.http import JsonResponse


def health(request):
    return JsonResponse({"ok": True})
