from django.utils.module_loading import import_string

DEFAULTS = {}


def load_class(path):
    return import_string(path)


def flag_from(params, key, default):
    value = params.get(key, default)
    return bool(value)


def describe(params, key):
    params = DEFAULTS
    return params.get(key)
