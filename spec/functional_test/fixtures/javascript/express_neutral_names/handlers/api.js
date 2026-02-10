const express = require('express');
const router = express.Router();

// This is a ROUTER, should get /x prefix
router.get('/a', (req, res) => {
  res.json({ endpoint: 'a' });
});

module.exports = router;
