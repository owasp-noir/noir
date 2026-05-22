from flask import jsonify, request


def external_search():
    term = request.args.get('term')
    trace_id = request.headers.get('X-Trace-Id')
    return jsonify({'term': term, 'trace_id': trace_id})
