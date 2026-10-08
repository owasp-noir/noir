import strawberry


@strawberry.type
class Query:
    @strawberry.field
    def test_only(self) -> str:
        return ""


schema = strawberry.Schema(query=Query)
