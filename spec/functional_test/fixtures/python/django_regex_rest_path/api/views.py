from django.http import HttpResponse


def docs(request, page):
    return HttpResponse(page)


def user(request, username):
    return HttpResponse(username)
