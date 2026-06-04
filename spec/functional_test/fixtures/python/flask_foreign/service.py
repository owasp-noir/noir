# A FastAPI handler file in the same repo. It uses `@app.get`/`@app.post`
# decorators and never mentions flask. The Flask analyzer must NOT claim
# it (mislabeling its routes python_flask); the FastAPI analyzer owns it.
from fastapi import FastAPI

app = FastAPI()


@app.get("/fastapi-items")
def list_items():
    return []


@app.post("/fastapi-items")
def create_item(name: str):
    return {"name": name}
