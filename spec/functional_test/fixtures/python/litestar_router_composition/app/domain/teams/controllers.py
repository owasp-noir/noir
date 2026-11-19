from litestar import Controller, get


class TeamController(Controller):
    path = "/teams"

    @get()
    async def list_teams(self) -> list:
        return []
