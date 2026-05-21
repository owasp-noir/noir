const express = require('express');

const app = express();
const router = express.Router();
const publicRouter = express.Router();
const multiRouter = express.Router();
const importedRouter = require('./routes/imported');

const PUBLIC_PREFIX = '/public-api';
const API_PREFIX = '/api/v1';

router['get']('/bracket-literal', (req, res) => {
  const mode = req.query['mode'];
  const requestId = req.get('X-Request-Id');
  res.json({ mode, requestId });
});

publicRouter.get('/status', (req, res) => {
  const trace = req.cookies['traceId'];
  res.json({ trace });
});

multiRouter.post('/things/:thingId', (req, res) => {
  const { thingId } = req.params;
  const { display_name: displayName, enabled = true } = req.body;
  res.json({ thingId, displayName, enabled });
});

app.use('/api', router);
app.use(PUBLIC_PREFIX, publicRouter);
app.use([API_PREFIX, '/admin-api'], multiRouter);
app.use(PUBLIC_PREFIX, importedRouter);
app.use([API_PREFIX, '/admin-api'], importedRouter);

module.exports = app;
