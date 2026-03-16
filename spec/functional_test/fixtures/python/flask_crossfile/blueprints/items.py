from flask import Blueprint, request, jsonify

items_bp = Blueprint('items', __name__)

@items_bp.route('/items', methods=['GET'])
def list_items():
    _ = request.args.get('page')
    return jsonify({"items": []})

@items_bp.route('/items', methods=['POST'])
def create_item():
    data = request.get_json()
    name = data['name']
    return jsonify({"created": True})
