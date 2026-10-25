from django.urls import path

from registry import registry


def get_model_urls(app_label, model_name, detail=True):
    paths = []
    try:
        views = [
            view for view in registry["views"][app_label][model_name]
            if view["detail"] == detail
        ]
    except KeyError:
        return []
    for config in views:
        view_ = config["view"].as_view()
        url_path = f"{config['path']}/" if config["path"] else ""
        paths.append(path(url_path, view_, kwargs=config["kwargs"]))
    return paths
