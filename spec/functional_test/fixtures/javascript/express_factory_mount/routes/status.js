module.exports = (app) => {
  app.get('/status', (req, res) => res.json({ ok: true }));
};
