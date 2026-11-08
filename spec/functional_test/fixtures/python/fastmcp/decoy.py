from fastmcp import FastMCP

from plugins import Registry

mcp = FastMCP("decoy")
registry = Registry()


# Not a FastMCP server: its `custom_route` is not an HTTP route.
@registry.custom_route("/not-a-route", methods=["GET"])
def plugin_hook(event):
    return event
