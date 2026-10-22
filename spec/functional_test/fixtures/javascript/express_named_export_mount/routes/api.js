const express = require('express');
const apiRouter = express.Router();
const health = require('./health');
apiRouter.use('/v1', health);
module.exports = { apiRouter };
