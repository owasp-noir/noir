const { Router } = require('express');
const router = Router();

router.post('/login', (req, res) => {
  const email = req.body.email;
  res.cookie('sid', 'x');
  res.json({ email });
});

module.exports = { router };
