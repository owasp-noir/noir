import strawberry


@strawberry.type
class Book:
    title: str
    author: str

    @strawberry.field
    def page_count(self, chapter: int | None = None) -> int:
        return 0


@strawberry.type
class Unused:
    @strawberry.field
    def never_bound(self) -> str:
        return ""
