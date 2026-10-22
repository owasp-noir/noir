# A FastAPI router that only uses aiohttp as an outbound HTTP client.
# The router is mounted under /api/v1/auths, so a bare /signin is never served.
from aiohttp import BasicAuth, ClientSession
from fastapi import APIRouter

router = APIRouter()


@router.post("/signin")
async def signin():
    async with ClientSession(auth=BasicAuth("user", "pass")) as session:
        async with session.get("https://ldap.example.com/bind") as response:
            return await response.json()
