const express = require('express');

const router = express.Router();

router.route('/')
  .get((req, res) => res.json([]))
  .post((req, res) => res.json({ created: true }));

router.route('/:userId')
  .get((req, res) => res.json({}))
  .patch((req, res) => res.json({ updated: true }))
  .delete((req, res) => res.status(204).end());

module.exports = router;
