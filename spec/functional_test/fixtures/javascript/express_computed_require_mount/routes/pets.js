const express = require('express');
const router = express.Router();

router.get('/all', (req, res) => {
  res.json({ limit: req.query.limit });
});

module.exports = router;
