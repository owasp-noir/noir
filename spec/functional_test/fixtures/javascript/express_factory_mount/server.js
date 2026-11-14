const express = require('express');
const routes = require('./routes');
const status = require('./routes/status');

const app = express();
const router = express.Router();

app.use('/api', routes(router));

// Called on the app itself, not mounted: its routes stay at the root.
status(app);

app.listen(3000);
