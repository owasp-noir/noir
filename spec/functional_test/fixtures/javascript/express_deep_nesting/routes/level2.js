const express = require('express');
const router = express.Router();

// Level 2 has its own route
router.get('/status', (req, res) => res.json({ level: 2 }));

// Level 3: Mount level3Router at /admin
const level3Router = require('./level3');
router.use('/admin', level3Router);

module.exports = router;
