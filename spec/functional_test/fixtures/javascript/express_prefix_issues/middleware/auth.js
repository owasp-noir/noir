// Middleware only - no routes
module.exports = function auth(req, res, next) {
  // Check authentication
  if (req.headers.authorization) {
    next();
  } else {
    res.status(401).json({ error: 'Unauthorized' });
  }
};
