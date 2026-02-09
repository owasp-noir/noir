const express = require('express');
const router = express.Router();

// Level 1 has its own route
router.get('/info', (req, res) => res.json({ level: 1 }));

// Level 2: Mount level2Router at /v1
const level2Router = require('./level2');
router.use('/v1', level2Router);

module.exports = router;
