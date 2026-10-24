const vhost = require('vhost');

function initApps(config) {
  const parentApp = require('./web/parent')();
  const backendApp = require('./web/backend')();
  const frontendApp = require('./web/frontend')();

  // vhost picks the app by Host header; it adds no path prefix.
  parentApp.use(vhost(config.adminHost, backendApp));
  parentApp.use(vhost(config.siteHost, frontendApp));
  return parentApp;
}

module.exports = initApps;
