from fastmcp import FastMCP
from fastmcp.server.auth.providers.jwt import JWTVerifier
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse

mcp = FastMCP("demo", auth=JWTVerifier(jwks_uri="https://issuer.example/jwks", audience="demo"))


@mcp.tool
def add(a: int, b: int) -> int:
    return a + b


@mcp.custom_route("/health", methods=["GET"])
async def health(request: Request) -> PlainTextResponse:
    return PlainTextResponse("OK")


@mcp.custom_route("/items/{item_id}", methods=["GET", "DELETE"])
async def item(request: Request) -> JSONResponse:
    return JSONResponse({"id": request.path_params["item_id"], "q": request.query_params.get("q")})


@mcp.custom_route("/users/{user_id:int}", methods=["GET"])
async def user(request: Request) -> JSONResponse:
    return JSONResponse({"trace": request.headers.get("x-trace-id")})


@mcp.custom_route(
    "/webhook",
    ["POST"],
)
async def webhook(request: Request) -> JSONResponse:
    payload = await request.json()
    return JSONResponse({"event": payload["event"]})


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
