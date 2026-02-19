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

class NestedDefHandler(tornado.web.RequestHandler):
    def post(self):
        def validate(data):
            return True
        username = self.get_body_argument("username")
        self.write({"ok": True})

class InnerClassHandler(tornado.web.RequestHandler):
    class Config:
        strict = True

    def get(self):
        q = self.get_argument("q")
        self.write({"q": q})

    def delete(self):
        self.write({"deleted": True})
