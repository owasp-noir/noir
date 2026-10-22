from typing import Optional

import strawberry

from .types import Book


def get_books(info: strawberry.Info, author_name: Optional[str] = None, limit: int = 10) -> list[Book]:
    return []
