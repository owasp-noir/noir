'use strict';

module.exports = app => {
  app.router.get('/fixture-only', app.controller.home.index);
};
