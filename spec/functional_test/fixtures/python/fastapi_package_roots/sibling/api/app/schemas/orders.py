from pydantic import BaseModel

class OrderIn(BaseModel):
    customer_email: str
    amount: int
