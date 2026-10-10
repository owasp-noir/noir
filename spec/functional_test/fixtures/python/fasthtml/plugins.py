# Not a FastHTML module: an unrelated `rt` decorator is not a route.
from tracing import rt


@rt("/not-a-route")
def traced():
    return 1


@rt
def also_traced():
    return 2
