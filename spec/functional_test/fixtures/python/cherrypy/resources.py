import cherrypy


class Reports(object):
    @cherrypy.expose
    def index(self):
        return "reports index"

    @cherrypy.expose
    def latest(self, report_id):
        token = cherrypy.request.headers.get('X-Api-Token')
        return {"report_id": report_id, "token": token}
