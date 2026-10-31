from typing import Annotated, Any, Optional

from fastapi import Depends, HTTPException, Request

from deps import Anonymous, Authenticator, User

PUBLIC = {Anonymous, User}

positional_open = Authenticator({Anonymous, User})
constant_open = Authenticator(allowed_subjects=PUBLIC)


def Guard(*, allowed_subjects=None) -> Any:
    _authenticator = Authenticator(allowed_subjects=allowed_subjects or {User})

    async def dependency(subject: Annotated[Any, Depends(_authenticator)]):
        return subject

    return dependency


class TokenAuth:
    def __init__(self, auto_error: bool = True):
        self.auto_error = auto_error

    async def __call__(self, request: Request) -> Optional[str]:
        token = request.headers.get("Authorization")
        if not token:
            if self.auto_error:
                raise HTTPException(status_code=401, detail="Not authenticated")
            return None
        return token


optional_token = TokenAuth(auto_error=False)
required_token = TokenAuth()
MaybeToken = Annotated[Optional[str], Depends(TokenAuth(auto_error=False))]


class Limiter:
    def __init__(self, per_minute: int):
        self.per_minute = per_minute

    def __call__(self):
        if self.per_minute <= 0:
            raise HTTPException(status_code=403, detail="rate limited")


class Banned:
    def __call__(self, user=Depends(Authenticator(allowed_subjects={Anonymous, User}))):
        if user.is_banned:
            raise HTTPException(status_code=403)
        return user


limiter = Limiter(per_minute=60)
banned_check = Banned()
