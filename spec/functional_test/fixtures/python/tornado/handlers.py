import tornado.web
import json

class ApiHandler(tornado.web.RequestHandler):
    async def get(self):
        api_key = self.request.headers.get("X-API-Key")
        self.write({"status": "ok"})

    async def post(self):
        data = json.loads(self.request.body)
        self.write({"created": True})

class SearchHandler(tornado.web.RequestHandler):
    def get(self):
        tags = self.get_arguments("tags")
        q = self.get_argument("q")
        self.write({"results": []})
