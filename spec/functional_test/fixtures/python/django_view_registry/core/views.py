from django.conf import settings
from django.contrib.auth.mixins import AccessMixin

from registry import registry


class ConditionalLoginRequiredMixin(AccessMixin):
    def dispatch(self, request, *args, **kwargs):
        if settings.LOGIN_REQUIRED and not request.user.is_authenticated:
            return self.handle_no_permission()
        return super().dispatch(request, *args, **kwargs)


def register_model_view(model, name="", path=None, detail=True, kwargs=None):
    def _wrapper(cls):
        app_label = model._meta.app_label
        model_name = model._meta.model_name
        if model_name not in registry["views"][app_label]:
            registry["views"][app_label][model_name] = []
        registry["views"][app_label][model_name].append({
            "name": name,
            "view": cls,
            "path": path if path is not None else name,
            "detail": detail,
            "kwargs": kwargs or {},
        })
        return cls
    return _wrapper
