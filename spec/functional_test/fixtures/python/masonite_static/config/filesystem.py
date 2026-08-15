from masonite.environment import env
from masonite.utils.location import base_path


DISKS = {
    "default": "local",
    "local": {"driver": "file", "path": base_path("storage/framework/filesystem")},
}

STATICFILES = {
    # folder          # template alias
    "storage/static": "static/",
    "storage/public": "/",
}
