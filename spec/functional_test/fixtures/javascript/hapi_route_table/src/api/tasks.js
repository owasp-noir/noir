exports.taskRoutes = [
  { method: 'GET', path: '/tasks', handler: (request, h) => [] },
  { method: 'PUT', path: '/tasks/{id}', handler: (request, h) => request.payload },
];

// Exported but registered by no one.
exports.archivedRoutes = [
  { method: 'GET', path: '/tasks/archived', handler: () => [] },
];
