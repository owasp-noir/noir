import json
import sys
from importlib.metadata import version

from starlette.routing import Mount, Route

from app import app

if sys.argv[1:] == ["--version"]:
    print(version("fastapi"))
    sys.exit()


def http_routes(routes, prefix=""):
    for route in routes:
        path = prefix + route.path
        if isinstance(route, Mount):
            yield from http_routes(route.routes, path)
        elif isinstance(route, Route):
            for method in route.methods:
                yield {"method": method, "path": path}


rows = http_routes(app.routes)
print(json.dumps(sorted(rows, key=lambda row: (row["path"], row["method"])), indent=2))
