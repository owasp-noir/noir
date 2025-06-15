from robyn import Robyn

app = Robyn(__file__)

@app.get("/")
async def get_root(request):
    return "Hello Root"

@app.post("/submit")
def post_submit(request):
    return "Data submitted"

@app.put("/update/:item_id")
async def put_update(request):
    item_id = request.path_params["item_id"]
    return f"Updated item {item_id}"

@app.delete("/item/:id")
def delete_item(request, id: str): # path param 'id'
    return f"Deleted item {id}"
