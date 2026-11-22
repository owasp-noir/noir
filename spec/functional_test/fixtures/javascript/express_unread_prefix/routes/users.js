const express = require('express');
const router = express.Router();
router.get('/prefix-users', (req, res) => res.send('ok'));
module.exports = router;

const other = express.Router();
other.get('/separate', (req, res) => res.send('other'));
