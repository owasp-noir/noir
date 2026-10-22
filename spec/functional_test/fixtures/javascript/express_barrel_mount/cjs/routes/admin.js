const router = require('express').Router();
router.get('/stats', (req, res) => res.send('ok'));
module.exports = router;
