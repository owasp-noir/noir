from bottle import Bottle, request

app = Bottle()


@app.post('/tags')
def add_tags():
    # Bottle MultiDicts expose getall/getone for repeated keys.
    tag = request.forms.getall('tag')
    name = request.query.getall('name')
    # Negative: keys() is a dict-API method, not a parameter.
    all_keys = list(request.query.keys())
    return 'ok'
