const adminRoutes = [
  { method: 'GET', path: '/admin/stats', handler: (request, h) => request.headers['x-admin'] },
];

module.exports = { adminRoutes };
