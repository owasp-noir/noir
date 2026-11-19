from flask_restful import Api, Resource

restful_api = Api(prefix="/legacy")


class Ping(Resource):
    def get(self):
        return "pong"


restful_api.add_resource(Ping, "/ping")
