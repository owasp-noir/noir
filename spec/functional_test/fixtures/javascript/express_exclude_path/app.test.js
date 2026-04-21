const express = require('express');
const app = express();

// Test-only route — should be excluded via --exclude-path "*.test.js"
app.get('/test/should-not-appear', (req, res) => res.json({ ok: true }));

module.exports = app;
