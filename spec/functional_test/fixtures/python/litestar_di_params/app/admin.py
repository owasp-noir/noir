from litestar import Controller, get
from litestar.di import Provide


async def provide_page() -> int:
    return 1


class AdminController(Controller):
    path = "/api/admin"
    dependencies = {"page": Provide(provide_page)}

    @get("/stats")
    async def stats(self, page: int) -> dict:
        return {}
