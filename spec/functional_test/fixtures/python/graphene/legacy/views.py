# Not Graphene: same shapes, no graphene import.
from mylib import ObjectType, Schema, String


class Query(ObjectType):
    lookalike = String(name=String())


schema = Schema(query=Query)
