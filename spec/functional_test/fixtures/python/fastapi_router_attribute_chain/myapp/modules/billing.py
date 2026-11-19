from fastapi import APIRouter

router = APIRouter()


@router.get("/invoices")
def invoices():
    return []
