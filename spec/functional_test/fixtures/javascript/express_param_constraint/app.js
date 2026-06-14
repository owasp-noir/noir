const express = require('express');
const app = express();

// path-to-regexp param constraints: the `(...)` group after a `:param`
// narrows the match but is noise for the endpoint surface. Each route
// should normalize to the bare param (`:id`, `:name`, `:pk`) with no
// phantom param leaking from the constraint body.
app.get('/users/:id([0-9]+)', (req, res) => res.json({}));
app.get('/files/:name([a-z]+)', (req, res) => res.json({}));
app.delete('/items/:pk([0-9a-f-]+)', (req, res) => res.json({}));

app.listen(3000);
