from flask_restful import Resource


class ItemResource(Resource):
    def get(self, item_id):
        return {}

    def put(self, item_id):
        return {}

    def delete(self, item_id):
        return {}


class ItemListResource(Resource):
    def get(self):
        return {}

    def post(self):
        return {}
