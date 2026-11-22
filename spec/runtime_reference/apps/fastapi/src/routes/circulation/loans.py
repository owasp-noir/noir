from fastapi import APIRouter

loans = APIRouter(prefix="/loans")


@loans.get("/active")
@loans.get("/overdue")
def list_loans():
    return []


@loans.post("/checkout", status_code=201)
def checkout(book_id: str):
    return {"book_id": book_id}


@loans.get("/{loan_id}")
def details(loan_id: int):
    return {"loan_id": loan_id}


@loans.get("/{loan_id}/renewals")
@loans.get("/{loan_id}/receipts")
def history(loan_id: int):
    return {"loan_id": loan_id, "history": []}


@loans.post("/{loan_id}/renew")
@loans.post("/{loan_id}/return")
def update(loan_id: int):
    return {"loan_id": loan_id}


def receipt(loan_id: int):
    return {"receipt": loan_id}


loans.add_api_route("/{loan_id}/receipt", receipt, methods=["GET", "HEAD"])
loans.add_api_route("/{loan_id}/receipt", receipt, methods=["PUT", "DELETE"], include_in_schema=False)
