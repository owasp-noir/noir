const express = require('../lib/express');

module.exports = function setupParentApp() {
  const parentApp = express('parent');
  return parentApp;
};
