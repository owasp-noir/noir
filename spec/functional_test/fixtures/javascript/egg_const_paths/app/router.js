'use strict';
module.exports = app => {
  const { router, controller } = app;
  const prefix = '/api/v1';
  router.get('/control', controller.home.index);
  router.get(`${prefix}/users`, controller.home.index);
  router.post(prefix + '/users', controller.home.index);
};
