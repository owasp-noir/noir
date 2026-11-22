const shelves = ['fiction', 'reference'];

function page(router, path, handler) {
  router.get(path, handler);
  router.get(`/feed${path}`, handler);
}

function installShelves(router, base) {
  for (const shelf of shelves) {
    page(router, `${base}/${shelf}/:id`, (req, res) => res.send(req.params.id));
  }
  configuredShelves().forEach(shelf => {
    page(router, `${base}/custom/${shelf}`, (req, res) => res.send('custom'));
  });
}

function configuredShelves() { return JSON.parse(process.env.SHELVES || '[]'); }

module.exports = { installShelves };
