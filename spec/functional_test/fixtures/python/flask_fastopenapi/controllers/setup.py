from controllers.fastopenapi import console_router


@console_router.get(
    "/setup",
    tags=["console"],
)
def get_setup_status():
    return {"step": "finished"}


@console_router.post("/setup", status_code=201)
def setup_system(payload):
    return {"result": "success"}
