'use strict';

module.exports = app => {
  const admin = app.router.namespace('/admin');
  admin.post('/reports', app.controller.admin.reportCenter.create);
};
