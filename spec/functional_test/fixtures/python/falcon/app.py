import falcon


class ThingsResource:
    def on_get(self, req, resp):
        q = req.get_param('q')
        limit = req.params.get('limit')
        resp.media = {'things': [], 'q': q, 'limit': limit}

    def on_post(self, req, resp):
        data = req.media
        resp.status = falcon.HTTP_201


class ThingResource:
    def on_get(self, req, resp, thing_id):
        api_key = req.get_header('X-API-Key')
        resp.media = {'id': thing_id, 'api_key': api_key}

    def on_delete(self, req, resp, thing_id):
        resp.status = falcon.HTTP_204

    # Suffix-based responder for /things/{thing_id}/items
    def on_get_item(self, req, resp, thing_id):
        session = req.cookies['session']
        resp.media = {'id': thing_id, 'session': session}

    def on_post_item(self, req, resp, thing_id):
        body = req.media
        resp.status = falcon.HTTP_201


class AuthResource:
    def on_post(self, req, resp):
        data = req.media
        token = req.cookies.get('auth_token')
        resp.media = {'ok': True}


class UploadResource:
    def on_put(self, req, resp, name):
        stream = req.bounded_stream
        resp.status = falcon.HTTP_200


app = falcon.App()
app.add_route('/things', ThingsResource())
app.add_route('/things/{thing_id:int}', ThingResource())
app.add_route('/things/{thing_id:int}/items', ThingResource(), suffix='item')
app.add_route('/auth', AuthResource())
app.add_route('/uploads/{name}', UploadResource())
