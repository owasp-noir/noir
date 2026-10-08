import asyncio
from typing import AsyncGenerator

import strawberry


@strawberry.type
class Subscription:
    @strawberry.subscription
    async def count_up(self, target: int = 100) -> AsyncGenerator[int, None]:
        for i in range(target):
            yield i
            await asyncio.sleep(0.5)
