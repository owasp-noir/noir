const restify = require('restify');

// The server is `srv`, not `server`; Restify also aliases OPTIONS as `opts`.
const srv = restify.createServer();

srv.get('/a', (req, res, next) => next());
srv.post({ path: '/b' }, (req, res, next) => {
  const name = req.body.name;
  res.send({ name });
  return next();
});
srv.opts('/d', (req, res, next) => {
  const origin = req.query.origin;
  res.send(204);
  return next();
});

// A plain object call carrying no handler is not a route.
const cache = { get: (spec) => spec };
cache.get({ path: '/cached' });

srv.listen(8080);
