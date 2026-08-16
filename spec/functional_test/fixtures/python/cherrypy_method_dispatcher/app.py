import cherrypy


@cherrypy.expose
class Generator(object):
    def GET(self):
        return cherrypy.session.get('mystring', '')

    def POST(self, length=8):
        return 'x' * int(length)

    def PUT(self, value):
        cherrypy.session['mystring'] = value

    def DELETE(self):
        cherrypy.session.pop('mystring', None)


class Item(object):
    exposed = True

    def GET(self, item_id):
        token = cherrypy.request.headers.get('X-Api-Token')
        return {"id": item_id, "token": token}

    def POST(self, item_id, name=None):
        return {"id": item_id, "name": name}


class Root(object):
    generator = Generator()
    item = Item()

    @cherrypy.expose
    def index(self):
        return "REST demo"


if __name__ == '__main__':
    conf = {
        '/': {
            'request.dispatch': cherrypy.dispatch.MethodDispatcher(),
        }
    }
    cherrypy.quickstart(Root(), '/', conf)
