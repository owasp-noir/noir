const express = require('express');
const app = express();

app.get('/health', (req, res) => res.json({ ok: true }));
app.post('/api/orders', (req, res) => res.json({}));
app.use('/files', (req, res) => {
  res.status(404).send('missing');
});

app.listen(3000);
