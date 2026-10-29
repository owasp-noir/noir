from cadwyn import VersionedAPIRouter

from app import variables

authenticated_router = VersionedAPIRouter()
authenticated_router.include_router(variables.router, prefix="/variables")
