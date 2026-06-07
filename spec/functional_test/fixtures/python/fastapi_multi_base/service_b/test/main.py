from fastapi import FastAPI

app = FastAPI()


@app.get("/should-not-appear")
def test_route():
    return {"test": True}
