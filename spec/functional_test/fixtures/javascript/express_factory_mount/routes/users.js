module.exports = (router) => {
  router.route('/v2/users')
    .get((req, res) => res.json([]))
    .post((req, res) => res.status(201).end());

  router.get('/v2/users/:id', (req, res) => res.json({ id: req.params.id }));
};
