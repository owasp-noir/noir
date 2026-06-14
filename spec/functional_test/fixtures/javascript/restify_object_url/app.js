const restify = require('restify');
const server = restify.createServer();

// Object route spec — restify accepts `url` as the path key (alongside
// `name`), not just `path`.
server.get({ url: '/foo/:id', name: 'GetFoo' }, function (req, res, next) {
  res.send({ id: req.params.id });
  next();
});

server.post({ path: '/bar' }, function (req, res, next) {
  res.send({});
  next();
});

server.listen(8080);
