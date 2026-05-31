from . import reports_bp


@reports_bp.route('/reports', methods=['GET'])
def list_reports():
    return {"reports": []}
