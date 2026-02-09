const express = require('express');
const router = express.Router();

// This should be prefixed with /orders
router.get('/pending', (req, res) => {
  res.json([]);
});

router.post('/create', (req, res) => {
  const { product } = req.body;
  res.json({ product });
});

module.exports = router;
