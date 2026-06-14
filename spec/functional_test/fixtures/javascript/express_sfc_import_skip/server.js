const express = require('express');
const app = express();
app.get('/api/health', (req, res) => res.json({ ok: true }));
app.listen(3000);
