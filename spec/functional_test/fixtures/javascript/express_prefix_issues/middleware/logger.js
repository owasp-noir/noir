// Middleware only - no routes
module.exports = function logger(req, res, next) {
  console.log(`${req.method} ${req.url}`);
  next();
};
