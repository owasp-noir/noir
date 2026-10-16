const express = require('express');

const app = express();

app.get('/health', (req, res) => res.json({ ok: true }));
app.post('/api/items', (req, res) => res.json({}));

// A receiver the file builds from express() is a router whatever it is called.
const http = express();
http.get('/named-http', (req, res) => res.json({}));

app.listen(3000);
