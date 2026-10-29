from dataclasses import dataclass

from pydantic import BaseModel


@dataclass
class AccountLogin:
    """Login form.

    Note: both fields are required.
    """

    username: str
    password: str


class UserBase(BaseModel):
    email: str


# Inherits fields this pass does not follow: keep a plain `data` param.
class UserCreate(UserBase):
    password: str
