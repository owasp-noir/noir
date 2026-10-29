from dataclasses import dataclass
from typing import Annotated

from litestar import Controller, post
from litestar.di import Provide
from litestar.enums import RequestEncodingType
from litestar.params import Body

from app.schemas import AccountLogin, UserCreate
from app.services import create_service_dependencies


class UserService:
    pass


class RefreshTokenService:
    pass


async def provide_users_service() -> UserService:
    return UserService()


@dataclass
class ForgotPassword:
    email: str


class AccessController(Controller):
    path = "/api/access"
    dependencies = create_service_dependencies(
        RefreshTokenService,
        key="refresh_token_service",
    ) | {"users_service": Provide(provide_users_service)}

    @post("/forgot-password")
    async def forgot_password(self, users_service: UserService, data: ForgotPassword) -> None:
        return None

    @post("/login")
    async def login(
        self,
        users_service: UserService,
        refresh_token_service: RefreshTokenService,
        data: Annotated[AccountLogin, Body(media_type=RequestEncodingType.URL_ENCODED)],
    ) -> None:
        return None

    @post("/signup")
    async def signup(self, data: UserCreate) -> None:
        return None
