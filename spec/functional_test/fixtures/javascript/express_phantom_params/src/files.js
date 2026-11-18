const app = require('express')();

// Unnamed wildcards are read by position.
app.get('/files/*', (req, res) => res.send(req.params[0] + req.params['0']));
