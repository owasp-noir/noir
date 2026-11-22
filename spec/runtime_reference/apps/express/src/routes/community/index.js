const { registerPage } = require('./pages');

const sections = ['clubs', 'events', 'reviews'];

function registerCommunity(app, mount) {
  for (const section of sections) {
    registerPage(app, `${mount}/${section}`, () => ({ section }));
  }
  registerPage(app, `${mount}/clubs/:club`, req => ({ club: req.params.club }));
  app.post(`${mount}/clubs/:club/join`, (_req, res) => res.sendStatus(202));
  app.delete(`${mount}/clubs/:club/membership`, (_req, res) => res.sendStatus(204));
}

module.exports = { registerCommunity };
