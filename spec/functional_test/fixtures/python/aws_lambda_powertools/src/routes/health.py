from aws_lambda_powertools.event_handler.router import Router

router = Router()


@router.get("/health")
def health():
    return {"ok": True}
