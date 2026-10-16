// `ab_test` is an A/B-test feature router, not a test: it imports express and
// has no test harness, so its routes are served.
const express = require('express');
const router = express.Router();

router.post('/assign', (req, res) => res.json({}));

module.exports = router;
