const users = require('./users');

module.exports = (router) => {
  users(router);
  require('./notes')(router);
  return router;
};
