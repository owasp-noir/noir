"""
Flask test fixture for advanced features:
- Blueprint shortcut decorators (@bp.get, @bp.post, etc.)
- MethodView class-based views
- add_url_rule with view assignments
"""
from flask import Flask, Blueprint, request, jsonify
from flask.views import MethodView

app = Flask(__name__)

# Blueprint with shortcut decorators
bp = Blueprint('api', __name__, url_prefix='/api')

@app.get('/app-get')
def app_get():
    """Test app-level GET shortcut"""
    return jsonify({'method': 'GET'})

@app.post('/app-post')
def app_post():
    """Test app-level POST shortcut"""
    return jsonify({'method': 'POST'})

@bp.get('/bp-get')
def bp_get():
    """Test blueprint GET shortcut"""
    return jsonify({'method': 'GET'})

@bp.post('/bp-post')
def bp_post():
    """Test blueprint POST shortcut"""
    data = request.form.get('data')
    return jsonify({'method': 'POST', 'data': data})

@bp.put('/bp-put')
def bp_put():
    """Test blueprint PUT shortcut"""
    return jsonify({'method': 'PUT'})

@bp.patch('/bp-patch')
def bp_patch():
    """Test blueprint PATCH shortcut"""
    return jsonify({'method': 'PATCH'})

@bp.delete('/bp-delete')
def bp_delete():
    """Test blueprint DELETE shortcut"""
    return jsonify({'method': 'DELETE'})

# MethodView class-based views
class UserAPI(MethodView):
    """MethodView with multiple HTTP methods"""

    def get(self, user_id=None):
        """GET method - list or retrieve user"""
        if user_id is None:
            return jsonify({'users': []})
        username = request.args.get('username')
        return jsonify({'user_id': user_id, 'username': username})

    def post(self):
        """POST method - create user"""
        username = request.form['username']
        email = request.json.get('email')
        return jsonify({'created': username, 'email': email})

    def put(self, user_id):
        """PUT method - update user"""
        data = request.json
        return jsonify({'updated': user_id, 'data': data})

    def delete(self, user_id):
        """DELETE method - delete user"""
        return jsonify({'deleted': user_id})

class ItemAPI(MethodView):
    """MethodView with query parameters"""

    def get(self):
        """GET method with query params"""
        page = request.args.get('page')
        return jsonify({'page': page})

    def post(self):
        """POST method with JSON body"""
        name = request.json.get('name')
        return jsonify({'name': name})

class AsyncAPI(MethodView):
    """Async MethodView (Flask 2.0+)"""

    async def get(self):
        """Async GET method"""
        category = request.args.get('category')
        return jsonify({'category': category})

    async def post(self):
        """Async POST method"""
        title = request.json.get('title')
        return jsonify({'title': title})

@bp.post('/get-json')
def use_get_json():
    """Test request.get_json() detection"""
    payload = request.get_json()
    action = payload.get('action')
    return jsonify({'action': action})

# Register MethodView with add_url_rule
user_view = UserAPI.as_view('user_api')
bp.add_url_rule('/users', view_func=user_view, methods=['GET', 'POST'])
bp.add_url_rule('/users/<int:user_id>', view_func=user_view, methods=['GET', 'PUT', 'DELETE'])

item_view = ItemAPI.as_view('item_api')
bp.add_url_rule('/items', view_func=item_view, methods=['GET', 'POST'])

async_view = AsyncAPI.as_view('async_api')
bp.add_url_rule('/async', view_func=async_view, methods=['GET', 'POST'])

# add_url_rule without explicit methods (should infer from class)
bp.add_url_rule('/items-inferred', view_func=ItemAPI.as_view('item_inferred'))

# Register blueprint
app.register_blueprint(bp)

if __name__ == '__main__':
    app.run(debug=True)
