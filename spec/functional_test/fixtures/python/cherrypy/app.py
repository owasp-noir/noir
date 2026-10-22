import cherrypy

from resources import Reports


class Users(object):
    def __init__(self):
        self.reports = Reports()

    @cherrypy.expose
    def index(self):
        return "users index"

    @cherrypy.expose
    def profile(self, user_id):
        session = cherrypy.request.cookie['session_id'].value
        return {"user_id": user_id, "session": session}

    @cherrypy.expose
    def search(self, query=None):
        region = cherrypy.request.params.get('region')
        return {"query": query, "region": region}

    @cherrypy.expose
    def default(self, *args, **kwargs):
        return {"args": args}


class Root(object):
    users = Users()

    @cherrypy.expose
    def index(self):
        return "Hello World!"

    @cherrypy.expose
    def generate(self, length=8):
        return ''.join(['a'] * int(length))


if __name__ == '__main__':
    cherrypy.quickstart(Root(), '/')
