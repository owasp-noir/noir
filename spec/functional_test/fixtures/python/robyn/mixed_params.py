from robyn import Robyn

app = Robyn(__file__)

@app.get("/search/:category")
async def search_items(request, category: str, q: str, limit: int = 10): # path 'category', query 'q', 'limit'
    return f"Search in {category} for {q} with limit {limit}"

# Test raw string path
@app.post(r"/raw/:data_point")
def post_raw_data(request, data_point: str, value: float): # path 'data_point', query 'value'
    return "Raw data"
