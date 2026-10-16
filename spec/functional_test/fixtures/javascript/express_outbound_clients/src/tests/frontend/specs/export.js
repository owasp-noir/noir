// Browser-side helper run by the page, not by node: `api` is a client here.
function exportHtml(link, done) {
  api.get(`${link}/export/html`, function (data) {
    done(data);
  });
}
