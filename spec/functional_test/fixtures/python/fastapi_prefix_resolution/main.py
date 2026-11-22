import os

from fastapi import APIRouter, FastAPI

from prefixes import API_PREFIX, actual_router, exported as public_router
from routes import outer_router
from settings import settings

BASE = os.environ.get("API_BASE", "")
suffix = runtime_suffix()
app = FastAPI()

literal_router = APIRouter(prefix="/literal")
constant_router = APIRouter(prefix=API_PREFIX)
settings_router = APIRouter(prefix=settings.API_V1_STR)
unread_router = APIRouter(prefix=settings.RUNTIME_PREFIX)
tail_router = APIRouter(prefix=BASE + "/router-v1")
fstring_router = APIRouter(prefix=f"{settings.RUNTIME_PREFIX}/f-v1")
env_tail_router = APIRouter(prefix=os.getenv("API_ROOT", "") + "/env-v1")
call_router = APIRouter(prefix=make_prefix())
gap_router = APIRouter(prefix=BASE + "/ignored" + suffix)
relative_router = APIRouter(prefix=BASE + "relative")
variable_router = APIRouter(prefix=UNRESOLVED_PREFIX)
leading_runtime_router = APIRouter(prefix="/leading" + settings.RUNTIME_SUFFIX)
include_tail_router = APIRouter()
include_unread_router = APIRouter()
nested_parent = APIRouter(prefix="/nested")
nested_child = APIRouter(prefix=BASE + "/child")
nested_parent.include_router(nested_child, prefix=BASE + "/mount")


@literal_router.get("/path")
def literal_path():
    return {}


@constant_router.get("/path")
def constant_path():
    return {}


@settings_router.get("/path")
def settings_path():
    return {}


@unread_router.get("/unread")
def unread_path():
    return {}


@tail_router.get("/router")
def router_tail_path():
    return {}


@fstring_router.get("/fstring")
def fstring_path():
    return {}


@env_tail_router.get("/env")
def env_tail_path():
    return {}


@call_router.get("/call")
def call_path():
    return {}


@gap_router.get("/gap")
def gap_path():
    return {}


@relative_router.get("/relative")
def relative_path():
    return {}


@variable_router.get("/variable")
def variable_path():
    return {}


@leading_runtime_router.get("/leading-runtime")
def leading_runtime_path():
    return {}


@include_tail_router.get("/include")
def include_tail_path():
    return {}


@include_unread_router.get("/include-unread")
def include_unread_path():
    return {}


@nested_parent.get("/health")
def nested_health():
    return {}


@nested_child.get("/nested-path")
def nested_path():
    return {}


@app.get("/health")
def health():
    return {}


app.include_router(literal_router)
app.include_router(constant_router)
app.include_router(settings_router)
app.include_router(unread_router)
app.include_router(tail_router)
app.include_router(fstring_router)
app.include_router(env_tail_router)
app.include_router(call_router)
app.include_router(gap_router)
app.include_router(relative_router)
app.include_router(include_tail_router, prefix=BASE + "/include-v1")
app.include_router(include_unread_router, prefix=os.environ["UNREAD_PREFIX"])
app.include_router(nested_parent)
app.include_router(outer_router, prefix=f"{settings.RUNTIME_PREFIX}/cross")


subapp = FastAPI()
app.mount(os.environ["SUBAPP_PATH"], subapp)


@subapp.get("/subapp-health")
def subapp_health():
    return {}

app.include_router(public_router, prefix="/public")
app.include_router(public_router, prefix="/verified")
app.include_router(actual_router, prefix="/verified")
