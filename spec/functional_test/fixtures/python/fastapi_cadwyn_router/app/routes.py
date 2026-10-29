from cadwyn import VersionedAPIRouter
from fastapi import APIRouter

router = VersionedAPIRouter()
plain = APIRouter()


@router.get("/{run_id}/state")
def get_state(run_id: str):
    return {}


@plain.get("/{dag_id}")
def get_dag(dag_id: str):
    return {}
