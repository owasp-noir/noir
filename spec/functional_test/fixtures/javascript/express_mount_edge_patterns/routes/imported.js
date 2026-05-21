const express = require('express');
const router = express.Router();

router.get('/imported', (req, res) => {
  const source = req.query.source;
  res.json({ source });
});

module.exports = router;
