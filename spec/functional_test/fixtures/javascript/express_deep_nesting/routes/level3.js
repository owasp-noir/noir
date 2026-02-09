const express = require('express');
const router = express.Router();

// Level 3 routes - these should resolve to /api/v1/admin/...
router.get('/users', (req, res) => res.json([]));
router.post('/users', (req, res) => res.status(201).json({}));

module.exports = router;
