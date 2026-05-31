from django.http import JsonResponse


def ping(request):
    return JsonResponse({"ok": True})


def items(request):
    return JsonResponse({"items": []})


def item_detail(request, item_id):
    return JsonResponse({"id": item_id})
