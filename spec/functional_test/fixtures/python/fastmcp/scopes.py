"""Plugin hooks, for example:

    hooks = FastMCP("example only")
"""

from fastmcp import FastMCP

from plugins import hooks

mcp = FastMCP("scopes")


@mcp.custom_route ("/spaced", methods=["GET"])
async def spaced(request):
    return request


def build_server():
    local = FastMCP("local")

    @local.custom_route("/local", methods=["POST"])
    async def local_route(request):
        return request

    return local


# Not FastMCP servers: a local bound to another object, a parameter that
# shadows the module-level `mcp`, and a name bound only in the docstring.
def build_plugin(registry):
    local = registry

    @local.custom_route("/not-a-route-scope", methods=["GET"])
    def plugin(event):
        return event

    return local


def register(mcp):
    @mcp.custom_route("/not-a-route-param", methods=["GET"])
    def hook(event):
        return event


@hooks.custom_route("/not-a-route-docstring", methods=["GET"])
def docstring_hook(event):
    return event
