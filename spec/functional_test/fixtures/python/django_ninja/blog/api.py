from ninja import Router

router = Router()


@router.get("/recent")
def recent(request, tag: str = None):
    return []
