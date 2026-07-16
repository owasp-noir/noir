from flask import Flask, request, jsonify

app = Flask(__name__)


@app.route('/search', methods=['GET'])
def search():
    # .get() (single value) already worked; .getlist() (repeated keys,
    # ?tags=a&tags=b) is the regression target.
    q = request.args.get('q')
    tags = request.args.getlist('tags')
    # Negatives: a dynamic (non-literal) key and a dict-API method must
    # NOT be reported as request parameters.
    dynamic = request.args.get(user_supplied_key)
    all_keys = list(request.args.keys())
    return jsonify({'q': q, 'tags': tags, 'dynamic': dynamic, 'all_keys': all_keys})


@app.route('/bulk', methods=['POST'])
def bulk():
    names = request.form.getlist('names')
    return jsonify({'names': names})
