from fastapi import APIRouter

router = APIRouter()


@router.get("/{variable_key}")
def get_variable(variable_key: str):
    return {}
