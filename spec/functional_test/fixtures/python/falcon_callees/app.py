import falcon
from db import list_items, save_item


class ItemResource:
    def on_get(self, req, resp):
        items = list_items()
        resp.media = items

    def on_post(self, req, resp):
        save_item(req.media)


app = falcon.App()
app.add_route("/items", ItemResource())
