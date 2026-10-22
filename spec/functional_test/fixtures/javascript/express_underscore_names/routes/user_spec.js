// "spec" here is the product concept (a user spec), not a mocha spec.
module.exports = function registerSpec(app) {
  app.post('/specs', (req, res) => res.json({ ok: true }));
};
