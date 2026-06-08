from robyn import Robyn, SubRouter

app = Robyn(__file__)
api = SubRouter(__file__, "/service-a")


@api.get("/items")
async def list_items():
    return {"items": []}
