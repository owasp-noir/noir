const express = require('express');
const passport = require('passport');
const { expressjwt } = require('express-jwt');

const app = express();

// Global auth middleware for /admin routes
app.use('/admin', passport.authenticate('jwt', { session: false }));

// Public route - no auth
app.get('/public', (req, res) => {
  res.json({ message: 'Public content' });
});

// Passport-protected route
app.get('/profile', passport.authenticate('jwt', { session: false }), (req, res) => {
  res.json({ user: req.user });
});

// JWT middleware protected route
app.post('/api/data', expressjwt({ secret: 'secret', algorithms: ['HS256'] }), (req, res) => {
  res.json({ data: [] });
});

// Generic auth middleware
app.get('/dashboard', requireAuth, (req, res) => {
  res.json({ dashboard: true });
});

// Unprotected API route
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

module.exports = app;
