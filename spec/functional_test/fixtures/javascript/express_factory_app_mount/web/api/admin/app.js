const express = require('../../../lib/express');
const routes = require('./routes');

module.exports = function setupAdminApp() {
  const adminApp = express('admin api');
  adminApp.use(routes());
  return adminApp;
};
