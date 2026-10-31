from fastapi import FastAPI

from items.endpoints import router as items_router

app = FastAPI()
app.include_router(items_router)
