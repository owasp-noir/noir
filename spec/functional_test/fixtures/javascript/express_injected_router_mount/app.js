'use strict';

const express = require('express');
const writeRoutes = require('./routes/write');
const groupsRoutes = require('./routes/write/groups');

const app = express();
const router = express.Router();

// The write routes are installed by handing the router to another module,
// so the module that owns the `/api/v3/*` mounts never sees where `router`
// itself is mounted.
writeRoutes.reload({ router: router });

// `groups` is additionally mounted here, with a prefix the scanner can
// resolve on its own.
app.use('/legacy', groupsRoutes());

app.use(router);

module.exports = app;
