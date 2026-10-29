from fastapi import FastAPI

app = FastAPI()


@app.get(
    "/one",
    description="""
    Returns things (see issue #12)
    """,
)
def one(q: str):
    return q


class PermissionsDependency:
    """
    Use it as follows:

    .. code-block:: python

        @app.get("/teapot/")
        async def teapot() -> dict:
            return {}
    """
