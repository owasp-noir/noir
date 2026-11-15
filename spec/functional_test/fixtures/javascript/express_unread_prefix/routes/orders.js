const express = require('express');
const router = express.Router();
router.post('/prefix-orders', (req, res) => res.send('ok'));
module.exports = router;
