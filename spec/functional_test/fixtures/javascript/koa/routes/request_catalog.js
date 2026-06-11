module.exports = [
  {
    method: 'GET',
    path: '/not-a-route',
    timeout: 1000,
  },
  {
    method: 'POST',
    path: '/webhook-template',
    description: 'outbound request metadata',
  },
];
