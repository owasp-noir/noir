from sanic import response
from sanic.request import Request


async def external_status(request: Request, item_id: int):
    trace = request.args.get('trace')
    record = request.json
    state = record.get('state')
    return response.json({'id': item_id, 'trace': trace, 'state': state})
