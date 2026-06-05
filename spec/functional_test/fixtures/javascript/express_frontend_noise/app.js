// Minimal real Express server. This is the ONLY file in the fixture
// that should contribute endpoints. The sibling frontend/generated
// files reproduce issue #1903: a tiny Express surface buried in a
// large frontend tree whose bundles and outbound API clients used to
// be dragged through the parser.
const express = require('express');
const app = express();
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.post('/api/login', (req, res) => {
  const username = req.body.username;
  res.json({ ok: true, username });
});

app.listen(3000);
module.exports = app;
