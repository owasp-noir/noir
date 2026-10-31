from typing import Annotated, Any

from fastapi import APIRouter, Depends

from external_sdk.types import ItemsRead
from flags import (
    Guard,
    MaybeToken,
    banned_check,
    constant_open,
    limiter,
    optional_token,
    positional_open,
    required_token,
)
from deps import Anonymous, User

router = APIRouter(prefix="/flags")


@router.get("/positional", dependencies=[Depends(positional_open)])
async def positional():
    return []


@router.get("/constant", dependencies=[Depends(constant_open)])
async def constant():
    return []


@router.get("/forwarded")
async def forwarded(subject: Annotated[Any, Depends(Guard(allowed_subjects={Anonymous, User}))]):
    return []


@router.get("/forwarded-default")
async def forwarded_default(subject: Annotated[Any, Depends(Guard())]):
    return []


@router.get("/optional-token")
async def opt_token(token=Depends(optional_token)):
    return []


@router.get("/maybe-token")
async def maybe_token(token: MaybeToken):
    return []


@router.get("/required-token")
async def req_token(token=Depends(required_token)):
    return []


@router.get("/limited", dependencies=[Depends(limiter)])
async def limited():
    return []


@router.get("/banned", dependencies=[Depends(banned_check)])
async def banned():
    return []


@router.get("/foreign")
async def foreign(subject: ItemsRead):
    return []
