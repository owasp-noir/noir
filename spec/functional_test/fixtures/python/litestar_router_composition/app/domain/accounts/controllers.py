from litestar import Controller, get, post


class AccessController(Controller):
    @post("/login")
    async def login(self) -> dict:
        return {}


class UserController(Controller):
    path = "/users"

    @get("/")
    async def list_users(self) -> list:
        return []
