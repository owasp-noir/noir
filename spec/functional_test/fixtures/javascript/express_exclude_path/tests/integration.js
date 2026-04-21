const express = require('express');
const app = express();

// Path-scoped test route — should be excluded via --exclude-path "tests/*"
app.get('/integration/should-not-appear', (req, res) => res.json({ ok: true }));

module.exports = app;
