const { feathers } = require('@feathersjs/feathers');
const express = require('@feathersjs/express');

const app = express(feathers());

require('./services/messages/messages')(app);
require('./services/reviews/reviews')(app);
require('./services/health/health')(app);
require('./services/logs/logs')(app);

module.exports = app;
