from ninja import Router

router = Router()


@router.get("/latest")
def latest(request, page: int = 1):
    return []
