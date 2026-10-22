from odoo import http
from odoo.http import request

ADDRESS_METHODS = ['GET']


class WebsiteShop(http.Controller):

    @http.route('/shop/cart', type='http', auth='public', csrf=False)
    def cart(self, access_token=None, **post):
        coupon = post.get('coupon')
        return request.render('website_sale.cart', {'coupon': coupon})

    @http.route([
        '/shop',
        '/shop/page/<int:page>',
        '/shop/category/<model("product.public.category"):category>',
    ], type='http', auth='public', website=True)
    def shop(self, page=0, category=None, search='', **kw):
        return request.render('website_sale.products', {})

    @http.route('/shop/cart/update_json', type='json', auth='public', methods=['POST'])
    def cart_update_json(self, product_id, add_qty=1, **kw):
        return {}

    @http.route('/my/orders/<int:order_id>/cancel', type='http', auth='user', methods=['POST'])
    def cancel_order(self, order_id, reason=None):
        note = request.params.get('note')
        return request.redirect('/my/orders')

    @http.route('/shop/payment/validate', type='jsonrpc', auth='user')
    def payment_validate(self, transaction_id):
        return {}

    @http.route(route=['/shop/address'], type='http', auth='public', methods=ADDRESS_METHODS)
    def address(self, partner_id=None):
        return request.render('website_sale.address', {})

    @http.route(route='/shop/address/submit', type='json', auth='public', methods=ADDRESS_METHODS)
    def address_submit(self, partner_id):
        return {}

    def _helper(self):
        return True


class WebsiteShopExtended(WebsiteShop):

    @http.route()
    def cart(self, access_token=None, **post):
        return super().cart(access_token=access_token, **post)
