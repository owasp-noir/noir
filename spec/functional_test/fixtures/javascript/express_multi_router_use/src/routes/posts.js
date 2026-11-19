const router = require('express').Router();
router.get('/posts', (req, res) => res.json([]));
module.exports = router;
