import tornado.web


class StandaloneHandler(tornado.web.RequestHandler):
    def get(self):
        self.write("ok")

    def post(self):
        self.write("created")


# A module-level handler list that is registered from a DIFFERENT module
# (there is no local `Application(...)` here). Large Tornado apps such as
# jupyterhub define their whole API this way, so it must be picked up by
# the module-level handler-list pass.
default_handlers = [
    (r"/standalone", StandaloneHandler),
    # A logging-style ("format string", lowercase-arg) tuple must NOT be
    # mistaken for a route — the 2nd element is not a handler class.
    ("processed %d items in %s", processed_count),
]
