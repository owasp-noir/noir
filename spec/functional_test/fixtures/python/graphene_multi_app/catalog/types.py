# No `graphene.Schema(...)` here: the schema is built by a project helper,
# so the conventional root name binds.
import graphene


class Query(graphene.ObjectType):
    product = graphene.String(slug=graphene.String())
