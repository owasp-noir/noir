from typing import ClassVar

import strawberry

from .resolvers import get_books
from .types import Book


@strawberry.type
class BookQuery:
    books: list[Book] = strawberry.field(resolver=get_books)

    @strawberry.field
    def book(self, info: strawberry.Info, book_id: strawberry.ID) -> Book | None:
        return None


@strawberry.type
class Query(BookQuery):
    greeting: str = "hello"
    cache_size: ClassVar[int] = 10

    @strawberry.field(name="serverVersion")
    def version(self) -> str:
        return "1.0"

    @strawberry.field
    async def search_books(self, root: "Query", search_term: str, max_results: int = 20) -> list[Book]:
        return []

    def helper(self) -> str:
        return "not a field"
