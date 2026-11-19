from srv.application import app


@app.get("/health")
def health():
    return {}


@app.post("/login")
def login(username: str, password: str):
    return {}
