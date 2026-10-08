from typing import Annotated

import strawberry

from .types import Book


def remove_book(book_id: strawberry.ID) -> bool:
    return True


@strawberry.type
class Mutation:
    delete_book: bool = strawberry.mutation(resolver=remove_book)

    @strawberry.mutation
    def add_book(
        self,
        title: str,
        author_name: Annotated[str, strawberry.argument(name="author")],
    ) -> Book:
        return Book(title=title, author=author_name)
