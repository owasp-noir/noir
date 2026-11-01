def detail_route(methods=["get"], **kwargs):
    def decorator(func):
        func.bind_to_methods = methods
        func.detail = True
        return func
    return decorator


def list_route(methods=["get"], **kwargs):
    def decorator(func):
        func.bind_to_methods = methods
        func.detail = False
        return func
    return decorator
