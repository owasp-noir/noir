const comments = require('./comments');

module.exports = function (router) {
  router.get('/v2/notes', (req, res) => res.json([]));
  comments(router);
};
