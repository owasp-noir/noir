// Middleware only - no routes
module.exports = function validate(req, res, next) {
  // Validate request
  if (req.body) {
    next();
  } else {
    res.status(400).json({ error: 'Invalid request' });
  }
};

// Not a router: an older version also exposed
// router.post('/validate', validate);
