// MIDDLEWARE - no routes, just a function
module.exports = function mw(req, res, next) {
  // Some middleware logic
  next();
};
