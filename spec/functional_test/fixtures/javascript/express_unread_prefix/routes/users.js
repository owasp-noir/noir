const express = require('express');
const router = express.Router();
router.get('/prefix-users', (req, res) => res.send('ok'));
module.exports = router;
