// The reader-facing page and the JSON feed use the same view model.
function registerPage(app, path, load) {
  app.get(path, (req, res) => {
    const page = load(req);
    res.type('text').send(page.club || page.section);
  });
  app.get(`/api${path}`, (req, res) => res.json(load(req)));
}

module.exports = { registerPage };
