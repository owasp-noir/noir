from sanic import Sanic, response

app = Sanic("mvapp")


@app.get('/search')
async def search(request):
    ids = request.args.getlist('ids')
    tag = request.args.get('tag')
    return response.json({})


@app.post('/bulk')
async def bulk(request):
    names = request.form.getlist('names')
    return response.json({})
