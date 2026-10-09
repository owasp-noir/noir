from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from admin import admin_app

app = FastAPI()
subapi = FastAPI()


@app.get("/app")
def read_main():
    return {"message": "Hello World from main app"}


@subapi.get("/sub")
def read_sub():
    return {"message": "Hello World from sub API"}


app.mount("/subapi", subapi)
app.mount(path="/admin", app=admin_app, name="admin")
app.mount("/static", StaticFiles(directory="static"), name="static")
