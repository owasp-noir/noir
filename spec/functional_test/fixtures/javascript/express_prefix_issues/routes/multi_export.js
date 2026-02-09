const express = require('express');

// Factory function that IS mounted (at /api)
function createPublicRouter() {
  const router = express.Router();
  router.get('/public', (req, res) => {
    res.json({ message: 'public endpoint' });
  });
  return router;
}

// Factory function that is NOT mounted
// This should NOT have any prefix applied to it
function createAdminRouter() {
  const router = express.Router();
  router.get('/admin', (req, res) => {
    res.json({ message: 'admin endpoint' });
  });
  return router;
}

module.exports = { createPublicRouter, createAdminRouter };
