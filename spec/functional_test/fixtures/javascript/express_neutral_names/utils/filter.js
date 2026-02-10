// MIDDLEWARE - no routes, just a function
module.exports = function filter(req, res, next) {
  // Some filter logic
  next();
};
