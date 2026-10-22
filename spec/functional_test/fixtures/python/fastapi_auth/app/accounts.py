from fastapi import APIRouter, Depends

from app.loose_deps import load_account
from . import strict_deps

router = APIRouter(prefix="/accounts")


@router.get("/")
def list_accounts(account=Depends(load_account)):
    return []


@router.delete("/{account_id}")
def delete_account(account_id: int, account=Depends(strict_deps.load_account)):
    return None
