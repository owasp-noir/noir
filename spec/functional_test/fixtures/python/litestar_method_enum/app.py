from typing import Annotated

from litestar import HttpMethod, Litestar, get, route
from litestar.params import Parameter


@route("/b", http_method=[HttpMethod.POST, HttpMethod.PUT])
async def b() -> None:
    pass


@route("/one", http_method=HttpMethod.DELETE)
async def one() -> None:
    pass


@route("/f", http_method=("PATCH", "HEAD"))
async def f() -> None:
    pass


@get("/d")
async def d(
    tok: str = Parameter(header="X-Token"),
    sid: str = Parameter(cookie="sid"),
    page: Annotated[int, Parameter(query="p", ge=1)] = 1,
    limit: int = 10,
    t: str = Parameter(title="x (y)", header="X-Y"),
) -> None:
    pass


app = Litestar(route_handlers=[b, one, f, d])
