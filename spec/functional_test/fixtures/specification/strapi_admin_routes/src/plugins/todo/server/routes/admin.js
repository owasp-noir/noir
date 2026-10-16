'use strict';

// Plugin routers default to the admin API (`/<plugin>/…`), they are not
// served under the content-API /api prefix.
module.exports = {
  type: 'admin',
  routes: [
    {
      method: 'GET',
      path: '/',
      handler: 'task.index',
    },
    {
      method: 'POST',
      path: '/tasks',
      handler: 'task.create',
    },
  ],
};
