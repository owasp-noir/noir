const express = require('../../lib/express');
const accountRoutes = require('./account');

module.exports = function setupMembersApp() {
  const membersApp = express('members');
  membersApp.use('/api/member', accountRoutes());
  membersApp.post('/api/session', (req, res) => res.sendStatus(201));
  return membersApp;
};
