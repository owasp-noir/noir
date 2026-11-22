import json
import sys
from importlib.metadata import version

from app import app

if sys.argv[1:] == ["--version"]:
    print(version("fastapi"))
    sys.exit()

rows = (
    {"method": method, "path": route.path}
    for route in app.routes
    for method in route.methods
)
print(json.dumps(sorted(rows, key=lambda row: (row["path"], row["method"])), indent=2))
