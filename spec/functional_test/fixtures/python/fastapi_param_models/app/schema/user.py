from fastapi import Form
from pydantic import Field

from .base import AppModel


class Registration(AppModel):
    full_name: str
    password_confirm: str
    email: str = Field(alias="mail")


class LoginForm:
    def __init__(
        self,
        username: str = Form(""),
        remember_me: bool = Form(False),
    ):
        self.username = username
        self.remember_me = remember_me


class FeedQuery(AppModel):
    include_notes: bool = True
    tz: str | None = None
