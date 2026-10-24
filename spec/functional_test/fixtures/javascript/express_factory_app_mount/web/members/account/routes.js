const express = require('../../../lib/express');

module.exports = function accountRoutes() {
  const router = express.Router();
  router.put('/', (req, res) => res.json(req.body));
  return router;
};
