const express = require('express');
const rateLimit = require('express-rate-limit');
const security = require('./lib/security');

const app = express();

// Decodes a cookie and continues: guards nothing, even app-wide.
app.use(security.updateAuthenticatedUsers());

// Path-mounted guard, with a non-guard beside it.
app.use('/rest/basket', security.isAuthorized(), security.appendUserId());

// Multi-line mount with no guard in it.
app.use('/rest/user/reset-password', rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 100,
}));

// Guard inline, same line as the route.
app.get('/rest/2fa/status', security.isAuthorized(), asyncHandler(twoFactorStatus));

// Guard on its own line of a multi-line registration.
app.post('/rest/2fa/setup',
  rateLimit({ windowMs: 5 * 60 * 1000, max: 100 }),
  security.isAuthorized(),
  asyncHandler(twoFactorSetup)
);

// The guard is the only argument: it is not the handler.
app.get('/api/Users', security.isAuthorized());
app.route('/api/Users/:id')
  .get(security.isAuthorized())
  .put(security.denyAll());

// A role check that answers 403.
app.get('/rest/order-history/orders', security.isAccounting(), asyncHandler(listOrders));

// Guarded by the /rest/basket mount above, nothing on the line.
app.get('/rest/basket/:id', asyncHandler(getBasket));

// Non-guard middleware only.
app.post('/rest/user/data-export', security.appendUserId(), asyncHandler(dataExport));

// The handler answers 401 to a wrong password: it is the handler, not a guard.
app.post('/rest/user/login', login);

// The mount is the guard; the handler's name is not.
app.use('/rest/user/authentication-details', security.isAuthorized());
app.get('/rest/user/authentication-details', asyncHandler(authenticatedUsers()));

// An error handler is not a guard for what follows it.
app.use(security.errorHandler);
app.get('/rest/users/list', asyncHandler(authenticatedUsers()));

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}
function twoFactorStatus(req, res) { res.json({ setup: false }); }
function twoFactorSetup(req, res) { res.json({ ok: true }); }
function listOrders(req, res) { res.json({ orders: [] }); }
function getBasket(req, res) { res.json({ id: req.params.id }); }
function dataExport(req, res) { res.json({ ok: true }); }
function login(req, res) {
  if (req.body.password !== 'fixture') return res.status(401).json({ error: 'wrong password' });
  res.json({ token: 'fixture' });
}
function authenticatedUsers() {
  return (req, res) => res.json({ users: [] });
}

module.exports = app;
