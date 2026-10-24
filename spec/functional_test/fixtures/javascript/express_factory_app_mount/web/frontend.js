const express = require('../lib/express');

module.exports = () => {
  const frontendApp = express('frontend');
  frontendApp.lazyUse('/members', require('./members'));
  return frontendApp;
};
