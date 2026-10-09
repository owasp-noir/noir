from aws_lambda_powertools.event_handler.api_gateway import Router

router = Router()


@router.put("/<order_id>")
def put_order(order_id):
    payload = router.current_event.json_body
    note = payload.get("note")
    return {"id": order_id, "note": note, "sku": router.current_event.json_body["sku"]}
