from fastapi import FastAPI

from app.views import init_views

app = FastAPI()
init_views(app)
