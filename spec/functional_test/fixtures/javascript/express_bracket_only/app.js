const express = require('express');

const router = express.Router();

router['get']('/users', (req, res) => {
  const limit = req.query.limit;
  res.json({ limit });
});

module.exports = router;
