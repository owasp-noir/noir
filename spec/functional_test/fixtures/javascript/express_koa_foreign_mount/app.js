const express = require('express');

const app = express();

app.get('/express-home', (req, res) => res.send('ok'));

app.listen(3000);
