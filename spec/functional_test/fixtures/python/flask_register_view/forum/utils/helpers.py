def register_view(bp_or_app, routes, view_func, **kwargs):
    for route in routes:
        bp_or_app.add_url_rule(route, view_func=view_func, **kwargs)


def remember_view(bp_or_app, routes, view_func):
    # records the view for a sitemap; registers nothing
    SITEMAP.extend(routes)
