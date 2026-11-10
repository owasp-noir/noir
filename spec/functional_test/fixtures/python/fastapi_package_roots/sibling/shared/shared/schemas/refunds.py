from pydantic import BaseModel

class RefundIn(BaseModel):
    order_id: str
    reason: str
