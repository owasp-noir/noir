const express = require('express');
const router = express.Router();
router.get('/recent', (req, res) => res.send('posts'));
exports.router = router;
