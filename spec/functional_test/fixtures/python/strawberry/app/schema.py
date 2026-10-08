import strawberry

from .mutations import Mutation
from .queries import Query
from .subscriptions import Subscription

schema = strawberry.Schema(query=Query, mutation=Mutation, subscription=Subscription)
