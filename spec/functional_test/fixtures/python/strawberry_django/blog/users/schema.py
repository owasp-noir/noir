import strawberry
import strawberry_django


@strawberry_django.type
class UserQuery:
    @strawberry_django.field
    def user_by_email(self, email_address: str) -> str:
        return email_address
