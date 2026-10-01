const express = require('express');
const app = express();

// path-to-regexp lets one segment hold several params joined by a literal
// `-` or `.` (both examples are from the Express routing guide). Each
// declares exactly the named params: no phantom `from-` swallowing the
// separator.
app.get('/flights/:from-:to', (req, res) => res.json(req.params));
app.get('/plantae/:genus.:species', (req, res) => res.json(req.params));

// Param names that share a prefix (`id` / `identifier`) are distinct params.
app.get('/users/:id/files/:identifier', (req, res) => res.json(req.params));

app.listen(3000);
