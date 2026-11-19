from litestar import Router, get


@get("/members")
async def members() -> list:
    return []


team_router = Router(path="/team-router", route_handlers=[members])
