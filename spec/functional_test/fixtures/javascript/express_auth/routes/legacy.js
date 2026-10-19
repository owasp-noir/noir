const router = require('express').Router();

// A router factory sends inside the routes it registers: mounted with
// `app.use('/legacy', legacyRoutes())`, it is a prefix, not a handler.
module.exports = function legacyRoutes() {
  router.get('/:gid', (req, res) => res.json({}));
  return router;
};
