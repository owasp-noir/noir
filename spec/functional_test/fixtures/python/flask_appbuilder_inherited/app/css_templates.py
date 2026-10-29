from app.base_api import BaseResourceApi
from app.constants import RouteMethod


class CssTemplateRestApi(BaseResourceApi):
    include_route_methods = RouteMethod.REST_MODEL_VIEW_CRUD_SET | {
        RouteMethod.RELATED,
        "bulk_delete",
    }
    resource_name = "css_template"
