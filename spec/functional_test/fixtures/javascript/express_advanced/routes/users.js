const express = require('express');
const router = express.Router();

router.get('/users', (req, res) => {
  const limit = req.query.limit;
  res.json({ limit });
});

router.post('/users', (req, res) => {
  const { name } = req.body;
  res.json({ name });
});

module.exports = router;
