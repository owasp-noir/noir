const LogService = require('feathers-memory');

module.exports = (app) => {
  app.use('/logs', new LogService());
  app.service('logs').hooks({});
};
