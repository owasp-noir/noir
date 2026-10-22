const router = require('express').Router();
router.get('/health', (req, res) => res.send('ok'));
module.exports = router;
