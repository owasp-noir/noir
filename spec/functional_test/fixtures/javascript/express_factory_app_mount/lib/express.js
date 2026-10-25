const express = require('express');

module.exports = (name) => {
  const app = express();
  app.set('name', name);

  // Mounts the app the factory returns, loading it on first request.
  app.lazyUse = function lazyUse(mountPath, requireFn) {
    app.use(mountPath, (req, res, next) => requireFn()(req, res, next));
  };

  return app;
};

module.exports.Router = () => express.Router();
