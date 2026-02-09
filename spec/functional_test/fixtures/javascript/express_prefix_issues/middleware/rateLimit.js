// Middleware only - no routes
module.exports = function rateLimit(req, res, next) {
  // Rate limiting logic
  next();
};
