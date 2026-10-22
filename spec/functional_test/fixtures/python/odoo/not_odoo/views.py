# A module that is not an Odoo controller: no `odoo` import, so the
# `http.route` decorator here must not produce endpoints.
import http


@http.route('/not-odoo')
def not_odoo():
    return None
