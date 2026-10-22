# Not Strawberry: same shapes, no strawberry import.
from mylib import field, Schema


class Query:
    @field
    def lookalike(self, name: str) -> str:
        return name


schema = Schema(query=Query)
