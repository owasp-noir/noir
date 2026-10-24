const express = require('../lib/express');
const { API_PATH } = require('../lib/paths');

module.exports = () => {
  const backendApp = express('backend');
  backendApp.lazyUse(API_PATH, require('./api'));
  return backendApp;
};
