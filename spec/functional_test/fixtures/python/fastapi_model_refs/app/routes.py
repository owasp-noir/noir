from fastapi import APIRouter

from app import base
from app.base import Owned as OwnedModel

router = APIRouter()


@router.post("/owners")
def create_owner(owner: base.Owned):
    return owner


@router.post("/owners/alias")
def create_owner_alias(owner: OwnedModel):
    return owner
