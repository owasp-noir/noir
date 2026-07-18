from typing import Optional

from ninja import Schema


class BlogIn(Schema):
    title: str
    body: str
    published: Optional[bool] = False
