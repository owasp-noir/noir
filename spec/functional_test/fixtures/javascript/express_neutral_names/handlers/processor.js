const express = require('express');
const router = express.Router();

// This is a ROUTER, should get /z prefix
router.get('/c', (req, res) => {
  res.json({ endpoint: 'c' });
});

module.exports = router;
