class ImportedReportResource:
    def on_get(self, req, resp):
        owner = req.get_param('owner')
        resp.media = {'owner': owner}

    def on_post(self, req, resp):
        payload = req.media
        name = payload['name']
        resp.media = {'name': name}
