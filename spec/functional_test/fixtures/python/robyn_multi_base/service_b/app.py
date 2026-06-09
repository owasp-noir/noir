from robyn import Robyn

app = Robyn(__file__)


@app.get("/local")
async def local():
    return {"ok": True}


# No `api` router is defined in this base. The analyzer should not reuse
# service A's `api` prefix for this unresolved decorator.
@api.get("/leaked")
async def leaked():
    return {"leaked": True}
