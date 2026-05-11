from fastapi import FastAPI
from db import save_user, audit_log

app = FastAPI()


@app.post("/users")
def create_user(name: str):
    user = save_user(name)
    audit_log(user)
    return {"id": user, "name": name}


@app.get("/healthz")
def healthz():
    return {"ok": True}
