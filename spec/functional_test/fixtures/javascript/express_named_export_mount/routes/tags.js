const express = require('express');
const router = express.Router();
router.get('/popular', (req, res) => res.send('tags'));
module.exports.router = router;
