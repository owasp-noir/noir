from litestar import get


# `page` is a DI key only in admin.py: here it is a query param.
@get("/search")
async def search(q: str, page: int) -> dict:
    return {}
