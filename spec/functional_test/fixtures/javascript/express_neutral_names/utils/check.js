// MIDDLEWARE - no routes, just a function
module.exports = function check(req, res, next) {
  // Some check logic
  next();
};
