from fastmcp import FastMCP as MCP

server = MCP("alias")


@server.custom_route("/alias", methods=["GET"])
async def alias(request):
    return request
