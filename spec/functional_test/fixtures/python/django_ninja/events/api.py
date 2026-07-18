from ninja import Router

router = Router()


@router.get("/")
def list_events(request):
    return []


@router.get("/{event_id}")
def event_details(request, event_id: int):
    return {"id": event_id}
