import graphene
from graphene import relay

import cookbook.ingredients.schema
from cookbook.recipes import schema as recipes_schema


class Query(cookbook.ingredients.schema.Query, recipes_schema.Query, graphene.ObjectType):
    node = relay.Node.Field()


class Mutation(cookbook.ingredients.schema.Mutation, graphene.ObjectType):
    pass


class Subscription(graphene.ObjectType):
    count_seconds = graphene.Int(up_to=graphene.Int())

    async def subscribe_count_seconds(root, info, up_to):
        yield 0


schema = graphene.Schema(query=Query, mutation=Mutation, subscription=Subscription)
