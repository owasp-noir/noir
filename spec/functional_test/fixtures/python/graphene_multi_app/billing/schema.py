import graphene


class Query(graphene.ObjectType):
    invoice = graphene.String(number=graphene.Int())


schema = graphene.Schema(query=Query)
