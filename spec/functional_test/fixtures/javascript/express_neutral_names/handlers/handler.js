const express = require('express');
const router = express.Router();

// This is ALSO a ROUTER - but processor should get the prefix, not this one
// (Since processor comes before handler in the .use() call)
router.get('/d', (req, res) => {
  res.json({ endpoint: 'd' });
});

module.exports = router;
