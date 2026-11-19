const express = require('express');
const app = express();
const router = express.Router();

router
  .get('/items', (req, res) => { res.json(req.query.page); })
  .post('/items', (req, res) => { res.json(req.body.name); })
  .delete('/items/:id', (req, res) => { res.json(1); });

router.get('/one', (req, res) => res.json(1)).post('/two', createHandler);

function createHandler(req, res) { res.json(req.body.title); }

app.use('/api', router);
