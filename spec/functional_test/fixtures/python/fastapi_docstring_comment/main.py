from fastapi import FastAPI

app = FastAPI()


@app.get(
    "/one",
    description="""
    Returns things (see issue #12)
    """,
)
def one(q: str):
    return q
