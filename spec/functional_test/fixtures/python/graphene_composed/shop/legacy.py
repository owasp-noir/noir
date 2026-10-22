# Not Graphene: an unrelated `ObjectType` root.
from mylib import ObjectType, String


class Subscription(ObjectType):
    lookalike = String(topic=String())
