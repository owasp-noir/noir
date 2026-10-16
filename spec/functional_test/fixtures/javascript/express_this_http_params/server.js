const express = require('express');
const registerRoutes = require('./routes');

const app = express();
app.get('/health', (req, res) => res.end('ok'));
registerRoutes(app);

app.listen(3000);
