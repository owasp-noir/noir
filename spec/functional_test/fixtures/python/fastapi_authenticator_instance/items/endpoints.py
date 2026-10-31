from typing import Any

from fastapi import APIRouter, Depends

from deps import Authenticator, AuthorizeRead, User, UserOrAnonymous, lenient, strict

from . import auth

router = APIRouter(prefix="/items")


@router.get("/")
async def list_items(subject: auth.ItemsRead):
    return []


@router.get("/browse")
async def browse(subject: auth.ItemsBrowse):
    return []


@router.get("/maybe")
async def maybe(subject: UserOrAnonymous):
    return []


@router.get("/mine")
async def mine(subject: AuthorizeRead):
    return []


@router.get("/org/{org_id}")
async def org(authz: auth.OrgAccess):
    return {}


@router.get("/scopes")
async def scopes(subject: Any = Depends(Authenticator(allowed_subjects={User}))):
    return []


@router.get("/open")
async def open_items():
    return []


@router.get("/strict", dependencies=[Depends(strict)])
async def strict_items():
    return []


@router.get("/lenient", dependencies=[Depends(lenient)])
async def lenient_items():
    return []
