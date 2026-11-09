from fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse


def create_server() -> FastMCP:
    server: FastMCP = FastMCP(name="factory-demo")

    @server.custom_route("/ready", methods=["GET"])
    async def ready(_request: Request) -> JSONResponse:
        return JSONResponse({"status": "ok"})

    return server


app = create_server().http_app(path="/api/mcp")
