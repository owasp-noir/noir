from django.http import JsonResponse
from django.views import View

from helpers import audit_log, build_profile, save_user


def create_user(request):
    name = request.POST.get('name')
    user = save_user(name)
    audit_log(user)
    return JsonResponse({'id': user, 'name': name})


class ProfileView(View):
    def get(self, request):
        data = build_profile()
        audit_log(data)
        return JsonResponse(data)

    def post(self, request):
        user = save_user('profile')
        audit_log(user)
        return JsonResponse({'id': user})
