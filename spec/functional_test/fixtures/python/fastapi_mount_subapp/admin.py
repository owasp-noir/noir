from fastapi import APIRouter, FastAPI

admin_app = FastAPI()
users = APIRouter(prefix="/users")


@users.get("/{user_id}")
def read_user(user_id: int):
    return {"user_id": user_id}


admin_app.include_router(users)
