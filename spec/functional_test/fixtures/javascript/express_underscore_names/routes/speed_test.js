// snake_case production name: "speed test" is the feature, not a test file.
module.exports = function registerSpeed(app) {
  app.get('/speed', (req, res) => res.json({ ok: true }));
};
