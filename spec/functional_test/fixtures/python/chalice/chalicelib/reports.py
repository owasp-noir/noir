from chalice import Blueprint

bp = Blueprint(__name__)


@bp.route('/daily')
def daily():
    day = bp.current_request.query_params['day']
    return {'day': day}


@bp.route('/')
def summary():
    return {}
