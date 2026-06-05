// Browser-served script under public/. Not minified, but by framework
// convention everything under public/ is static output, never a route
// registration. The `app.get('/public-leak', ...)` shape below would
// be misread as an Express route without the public/ path gate
// (issue #1903). No express import here, so the server-import
// exemption must NOT keep it alive.
(function () {
  const app = window.__widgetBus;
  app.get('/public-leak', function (q, r) {
    r.render();
  });
  app.post('/public-leak/submit', function (q, r) {
    r.send('ok');
  });
})();
