import strawberry
from strawberry.schema.config import StrawberryConfig
from strawberry.tools import merge_types

from blog.posts.schema import PostMutation, PostQuery
from blog.users.schema import UserQuery

Query = merge_types("Query", (UserQuery, PostQuery))

schema = strawberry.Schema(
    query=Query,  # merged from users + posts
    mutation=PostMutation,
    config=StrawberryConfig(auto_camel_case=False),
)
