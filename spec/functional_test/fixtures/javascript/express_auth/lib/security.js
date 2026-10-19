const { expressjwt } = require('express-jwt');
const jwt = require('jsonwebtoken');

const publicKey = process.env.JWT_PUBLIC_KEY || 'fixture-placeholder';

// Guards: each one can refuse the request.
const isAuthorized = () => expressjwt({ secret: publicKey, algorithms: ['HS256'] });
const denyAll = () => expressjwt({ secret: '' + Math.random(), algorithms: ['HS256'] });
const isAccounting = () => {
  return (req, res, next) => {
    if (req.user && req.user.role === 'accounting') {
      next();
    } else {
      res.status(403).json({ error: 'Malicious activity detected' });
    }
  };
};

// Not guards: these decode what they find and continue regardless.
const appendUserId = () => (req, res, next) => {
  req.body.UserId = req.user && req.user.id;
  next();
};
const updateAuthenticatedUsers = () => (req, res, next) => {
  const token = req.cookies.token;
  if (token) {
    jwt.verify(token, publicKey, (err, decoded) => {
      if (err === null) res.cookie('token', token);
    });
  }
  next();
};

// An error handler answers 401 for the guards; it is not one.
const errorHandler = (err, req, res, next) => {
  if (err.name === 'UnauthorizedError') return res.status(401).json({ error: 'invalid token' });
  next(err);
};

module.exports = { isAuthorized, denyAll, isAccounting, appendUserId, updateAuthenticatedUsers, errorHandler };
