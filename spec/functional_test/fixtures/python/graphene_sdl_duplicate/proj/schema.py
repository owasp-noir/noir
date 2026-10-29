import graphene


class Query(graphene.ObjectType):
    me = graphene.String()


schema = graphene.Schema(query=Query)
