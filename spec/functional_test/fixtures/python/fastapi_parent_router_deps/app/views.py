from fastapi import APIRouter

reports_router = APIRouter()
status_router = APIRouter()
jobs_router = APIRouter()
shared_router = APIRouter()


@reports_router.get("/reports")
def reports():
    return []


@status_router.get("/status")
def status():
    return {"ok": True}


@jobs_router.get("/jobs")
def jobs():
    return []


@shared_router.get("/shared")
def shared():
    return {}
