from django.http import JsonResponse


def invoices(request):
    return JsonResponse({"invoices": []})
