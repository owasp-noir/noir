from litestar import get, Litestar


# List-of-paths form: one endpoint per path string.
@get(["/", "/index"])
async def index() -> dict:
    return {}


@get(path=["/health", "/healthz", "/status"])
async def health() -> dict:
    return {"ok": True}


app = Litestar(route_handlers=[index, health])
