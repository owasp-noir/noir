from fastapi import FastAPI

from api import router
from versioning import add_routers

app = FastAPI()

add_routers(app, router)
