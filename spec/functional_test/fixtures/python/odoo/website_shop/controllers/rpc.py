from odoo.http import Controller, route


class RPC(Controller):

    @route(['/xmlrpc/2/<service>', '/xmlrpc/<service>'], auth="none", methods=["POST"], csrf=False)
    def xmlrpc_2(self, service):
        return None
