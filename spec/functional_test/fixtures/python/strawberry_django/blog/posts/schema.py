import strawberry


@strawberry.type
class PostQuery:
    recent_posts: list[str] = strawberry.field(default_factory=list)


@strawberry.type
class PostMutation:
    @strawberry.mutation
    def publish_post(self, post_id: strawberry.ID) -> bool:
        return True
