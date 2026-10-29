from django.urls import path


def rest_dispatch(request, **kwargs):
    pass


def rest_path(route, **handlers):
    return path(route, rest_dispatch, handlers)
