const express = require('express');
const router = express.Router();

// This is a ROUTER, should get /y prefix
router.get('/b', (req, res) => {
  res.json({ endpoint: 'b' });
});

module.exports = router;
