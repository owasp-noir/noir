const router = require('express').Router();

router.get('/list', (req, res) => res.json([]));

module.exports = router;
