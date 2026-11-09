from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import PlainTextResponse

mcp = FastMCP("sdk-demo")


@mcp.custom_route("/status", methods=["GET"])
async def status(request: Request) -> PlainTextResponse:
    return PlainTextResponse("up")


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
