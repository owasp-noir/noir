from dataclasses import dataclass


@dataclass
class AccountLogin:
    username: str
    password: str
