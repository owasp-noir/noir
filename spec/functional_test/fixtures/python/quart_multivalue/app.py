from quart import Quart, request, jsonify

app = Quart(__name__)


@app.route('/search', methods=['GET'])
async def search():
    ids = request.args.getlist('ids')
    category = request.args.get('category')
    return jsonify({'ids': ids, 'category': category})
