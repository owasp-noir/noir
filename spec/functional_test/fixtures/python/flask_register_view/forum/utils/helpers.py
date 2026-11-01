def register_view(bp_or_app, routes, view_func, **kwargs):
    for route in routes:
        bp_or_app.add_url_rule(route, view_func=view_func, **kwargs)


def remember_view(bp_or_app, routes, view_func):
    # records the view for a sitemap; registers nothing
    SITEMAP.extend(routes)


def register_v2(bp_or_app, routes, view_func):
    for route in routes:
        bp_or_app.add_url_rule("/v2" + route, view_func=view_func)


def register_if_enabled(bp_or_app, routes, view_func, **kwargs):
    if kwargs.pop("enabled", False):
        for route in routes:
            bp_or_app.add_url_rule(route, view_func=view_func, **kwargs)
