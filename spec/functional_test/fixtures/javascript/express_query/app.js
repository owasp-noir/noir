const express = require('express');

const app = express();
const router = express.Router();

// app.query
app.query('/search', (req, res) => {
  const q = req.query.q;
  res.json({ results: [] });
});

// router.query
router.query('/items', (req, res) => {
  const filter = req.query.filter;
  res.json({ items: [] });
});

// app.route().query() chaining
app.route('/filter')
  .query((req, res) => {
    const category = req.query.category;
    res.json({ filtered: [] });
  });

module.exports = app;
