from typing import Annotated, Any

from fastapi import Depends, Request


class Unauthorized(Exception):
    status_code = 401


class Anonymous:
    pass


class User:
    pass


async def get_subject(request: Request):
    return request.state.subject


class _Authenticator:
    def __init__(self, *, allowed_subjects, required_scopes=None):
        self.allowed_subjects = allowed_subjects
        self.required_scopes = required_scopes

    async def __call__(self, subject=Depends(get_subject)):
        if isinstance(subject, Anonymous):
            if Anonymous in self.allowed_subjects:
                return subject
            else:
                raise Unauthorized()
        return subject


def Authenticator(allowed_subjects, required_scopes=None) -> _Authenticator:
    return _Authenticator(allowed_subjects=frozenset(allowed_subjects), required_scopes=required_scopes)


_UserOrAnonymous = Authenticator(allowed_subjects={Anonymous, User})
UserOrAnonymous = Annotated[Any, Depends(_UserOrAnonymous)]

_WebUser = Authenticator(allowed_subjects={User})


async def _web_user(subject: Annotated[Any, Depends(_WebUser)]):
    return subject


WebUserSession = Annotated[Any, Depends(_web_user)]


def ScopeAuthorizer(required_scopes) -> Any:
    async def dependency(subject: WebUserSession):
        return subject

    return dependency


AuthorizeRead = Annotated[
    Any,
    Depends(ScopeAuthorizer({"read"})),
]


def OrgGuard(*, allowed_subjects=None) -> Any:
    _authenticator = Authenticator(
        allowed_subjects=allowed_subjects or {User},
    )

    async def dependency(org_id: int, subject: Annotated[Any, Depends(_authenticator)]):
        return subject

    return dependency


class StrictAuthenticator:
    def __init__(self, allowed):
        self.allowed = allowed

    def __call__(self, subject=Depends(get_subject)):
        if isinstance(subject, Anonymous):
            if Anonymous not in self.allowed:
                raise Unauthorized()
        return subject


strict = StrictAuthenticator(allowed={User})
lenient = StrictAuthenticator(allowed={Anonymous, User})
