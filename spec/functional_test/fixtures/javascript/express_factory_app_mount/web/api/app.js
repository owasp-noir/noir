const express = require('../../lib/express');

module.exports = function setupApiApp() {
  const apiApp = express('api');
  apiApp.lazyUse('/admin/', require('./admin/app'));
  return apiApp;
};
