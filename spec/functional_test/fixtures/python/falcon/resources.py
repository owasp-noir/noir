class WidgetResource:
    def on_get(self, req, resp, widget_id):
        trace_id = req.get_header('X-Trace-ID')
        resp.media = {'widget_id': widget_id, 'trace_id': trace_id}

    def on_patch(self, req, resp, widget_id):
        payload = req.media
        status = payload.get('status')
        resp.media = {'widget_id': widget_id, 'status': status}


class ExternalProfileResource:
    def on_get_detail(self, req, resp, profile_id):
        session = req.cookies.get('session')
        resp.media = {'profile_id': profile_id, 'session': session}
