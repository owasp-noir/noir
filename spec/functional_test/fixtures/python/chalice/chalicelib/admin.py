from chalice import Blueprint

admin_bp = Blueprint(__name__)


@admin_bp.route('/users/{uid}', methods=['DELETE'])
def delete_user(uid):
    return {}
