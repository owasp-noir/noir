from robyn import Robyn

app = Robyn(__file__)

async def handle_data(request):
    return "Data handler"

def handle_info(request, info_id: int, query_param: str = "default"): # path param 'info_id', query 'query_param'
    return f"Info {info_id} with {query_param}"

app.add_route(method="GET", endpoint="/data", handler=handle_data)
app.add_route(method="POST", endpoint="/info/:info_id", handler=handle_info)
