// The app is handed in under the name `http`: an ordinary parameter, not the
// Node module.
module.exports = function registerRoutes(http) {
  http.get('/ping', (req, res) => res.end('pong'));
  http.post('/echo', echoHandler);
};

function echoHandler(req, res) {
  res.json(req.body);
}
