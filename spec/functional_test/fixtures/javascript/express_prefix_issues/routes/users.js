const express = require('express');
const router = express.Router();

// This should be prefixed with /users (from app.use('/users', userRoutes, auth))
router.get('/list', (req, res) => {
  res.json([]);
});

router.post('/create', (req, res) => {
  const { name } = req.body;
  res.json({ name });
});

module.exports = router;
