const express = require('express');
const authRoute = require('./auth.route');
const userRoute = require('./user.route');

const router = express.Router();

// Mimics the hagopj13/node-express-boilerplate idiom: a config array
// driven through forEach. `router.use(r.path, r.route)` takes expressions,
// not string literals, so the mount-scanner's config-array handler has to
// resolve the entries to recover the real mount paths.
const defaultRoutes = [
  { path: '/auth', route: authRoute },
  { path: '/users', route: userRoute },
];

defaultRoutes.forEach((r) => {
  router.use(r.path, r.route);
});

module.exports = router;
