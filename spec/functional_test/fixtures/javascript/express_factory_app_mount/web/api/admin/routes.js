const express = require('../../../lib/express');

module.exports = function adminRoutes() {
  const router = express.Router();

  router.get('/posts', (req, res) => res.json([]));
  router.put('/posts/:id', (req, res) => res.json({ id: req.params.id }));

  return router;
};
