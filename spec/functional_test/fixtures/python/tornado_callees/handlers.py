import tornado.web

from helpers import audit_log, build_profile


class ProfileHandler(tornado.web.RequestHandler):
    async def get(self):
        data = await build_profile()
        audit_log(data)
        self.write(data)
