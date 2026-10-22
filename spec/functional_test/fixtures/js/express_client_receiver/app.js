'use strict';

const express = require('express');
const app = express();
const router = express.Router();

router.get('/users/:uid', (req, res) => res.json({}));
router.post('/users', (req, res) => res.json({}));

app.use('/api', router);
app.listen(3000);
