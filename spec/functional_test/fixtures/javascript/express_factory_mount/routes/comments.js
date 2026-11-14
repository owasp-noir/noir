module.exports = (router) => {
  router.delete('/v2/notes/:id/comments', (req, res) => res.status(204).end());
};
