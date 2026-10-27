from django.utils.module_loading import import_string


def load_class(path):
    return import_string(path)


def flag_from(params, key, default):
    value = params.get(key, default)
    return bool(value)
